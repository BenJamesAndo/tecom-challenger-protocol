param(
    [string]$TecomIP = "your.ip.address",
    [int]$Port = 3001
)

Write-Host "=== Tecom Titan Time Setter ===" -ForegroundColor Cyan
Write-Host "Target: ${TecomIP}:${Port}" -ForegroundColor Green
Write-Host ""

# CRC-16/MODBUS checksum calculation
function Get-CRC16Modbus {
    param([byte[]]$data)
    
    $crc = 0xFFFF
    foreach ($byte in $data) {
        $crc = $crc -bxor $byte
        for ($i = 0; $i -lt 8; $i++) {
            if (($crc -band 0x0001) -ne 0) {
                $crc = ($crc -shr 1) -bxor 0xA001
            } else {
                $crc = $crc -shr 1
            }
        }
    }
    return $crc
}

# Find the 2 checksum bytes that make the complete packet CRC equal to 0x37b1
function Get-TecomChecksum {
    param([byte[]]$packetData)
    
    $TARGET_CRC = 0x37b1
    $crcBeforeChecksum = Get-CRC16Modbus -data $packetData
    
    for ($byte1 = 0; $byte1 -le 0xFF; $byte1++) {
        for ($byte2 = 0; $byte2 -le 0xFF; $byte2++) {
            $testCrc = $crcBeforeChecksum
            
            # Apply CRC for byte1
            $testCrc = $testCrc -bxor $byte1
            for ($i = 0; $i -lt 8; $i++) {
                if (($testCrc -band 0x0001) -ne 0) {
                    $testCrc = ($testCrc -shr 1) -bxor 0xA001
                } else {
                    $testCrc = $testCrc -shr 1
                }
            }
            
            # Apply CRC for byte2
            $testCrc = $testCrc -bxor $byte2
            for ($i = 0; $i -lt 8; $i++) {
                if (($testCrc -band 0x0001) -ne 0) {
                    $testCrc = ($testCrc -shr 1) -bxor 0xA001
                } else {
                    $testCrc = $testCrc -shr 1
                }
            }
            
            if ($testCrc -eq $TARGET_CRC) {
                return @($byte1, $byte2)
            }
        }
    }
    
    throw "Could not calculate valid checksum!"
}

# Calculate month offset for date byte encoding
# Months 1-7: offset = month * 32
# Months 8-12: offset = (month - 8) * 32
function Get-MonthOffset {
    param([int]$month)
    
    if ($month -ge 1 -and $month -le 7) {
        return $month * 32
    } elseif ($month -ge 8 -and $month -le 12) {
        return ($month - 8) * 32
    }
    
    throw "Invalid month: $month"
}

# Message counter for tracking packets (can be any value, increments with each packet)
$script:messageCounter = 1

# Encode date/time using Tecom's proprietary encoding scheme
# Supports years 1990-2117 (two 64-year cycles)
function New-TecomTimePacket {
    param([DateTime]$timestamp)
    
    $year = $timestamp.Year
    $month = $timestamp.Month
    $day = $timestamp.Day
    $hour = $timestamp.Hour
    $minutes = $timestamp.Minute
    $seconds = $timestamp.Second
    
    # Validate year range (hardware limitation: only supports 1990-2053)
    if ($year -lt 1990 -or $year -gt 2053) {
        throw "Year $year not supported. Valid range: 1990-2053 (hardware limitation)"
    }
    
    # Encode DateByte (Byte 7): monthOffset + day
    $monthOffset = Get-MonthOffset -month $month
    $dateByte = $day + $monthOffset
    
    # Encode ModeByte (Byte 8):
    # This encodes BOTH year and month range:
    # Formula: ModeByte = (year - 1990) * 2 + monthRangeBit
    # Bits 1-7: (year - 1990) 
    # Bit 0: 1 for months 8-12, 0 for months 1-7
    $yearOffset = $year - 1990
    $modeByte = $yearOffset * 2
    
    # Set bit 0 if month is in high range (8-12)
    if ($month -ge 8) {
        $modeByte = $modeByte -bor 0x01
    }
    
    # Encode TimeByte1 (Byte 9): (minutes % 8) * 32 + (seconds / 2)
    $timeByte1 = (($minutes % 8) * 32) + [Math]::Floor($seconds / 2)
    
    # Encode TimeByte2 (Byte 10): hour * 8 + (minutes / 8)
    $timeByte2 = ($hour * 8) + [Math]::Floor($minutes / 8)
    
    # Increment message counter and wrap at 256
    $script:messageCounter = ($script:messageCounter + 1) % 256
    
    # Assemble packet (without checksum)
    # Packet structure (13 bytes):
    # Byte 0: Fixed (0x5e)
    # Byte 1: Usually 0x70 (purpose unknown, doesn't affect date/time)
    # Bytes 2-3: Fixed (0x8000)
    # Byte 4: Message counter (can be any value)
    # Bytes 5-6: Fixed middle bytes (0x1804)
    # Byte 7: DateByte = monthOffset + day
    # Byte 8: ModeByte = (year - 1990) * 2 + monthRangeBit
    # Byte 9: TimeByte1
    # Byte 10: TimeByte2
    # Bytes 11-12: CRC-16/MODBUS checksum
    $packet = [byte[]]@(
        0x5E, 0x70, 0x80, 0x00,  # Prefix (Byte 1 usually 0x70)
        $script:messageCounter,         # Message counter (increments each packet)
        0x18, 0x04,                     # Fixed middle bytes
        $dateByte,                      # DateByte (Byte 7)
        $modeByte,                      # ModeByte (Byte 8)
        $timeByte1,                     # TimeByte1 (Byte 9)
        $timeByte2                      # TimeByte2 (Byte 10)
    )
    
    # Calculate and append checksum
    $checksum = Get-TecomChecksum -packetData $packet
    $packet += $checksum[0]
    $packet += $checksum[1]
    
    return $packet
}

try {
    # Get current time
    $currentTime = Get-Date
    Write-Host "Current PC time: $($currentTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
    Write-Host ""
    
    # Generate packet
    $packet = New-TecomTimePacket -timestamp $currentTime
    
    # Display packet
    $hexString = ($packet | ForEach-Object { $_.ToString("X2") }) -join ":"
    Write-Host "Generated packet:" -ForegroundColor Yellow
    Write-Host "  $hexString" -ForegroundColor Cyan
    Write-Host "  Length: $($packet.Length) bytes" -ForegroundColor Gray
    
    # Verify CRC
    $finalCrc = Get-CRC16Modbus -data $packet
    Write-Host "  Final CRC: 0x$($finalCrc.ToString('X4')) (should be 0x37B1)" -ForegroundColor Gray
    Write-Host ""
    
    # Send UDP packet
    Write-Host "Sending time-set packet to Tecom Titan..." -ForegroundColor Yellow
    
    $udpClient = New-Object System.Net.Sockets.UdpClient
    $bytesSent = $udpClient.Send($packet, $packet.Length, $TecomIP, $Port)
    
    Write-Host "Sent $bytesSent bytes to ${TecomIP}:${Port}" -ForegroundColor Green
    Write-Host ""
    Write-Host "Time set successfully!" -ForegroundColor Green
    
    $udpClient.Close()
    
} catch {
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
}
