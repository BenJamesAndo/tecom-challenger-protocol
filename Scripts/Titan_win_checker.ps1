# Check-Titan.ps1
# Checks if Tecom Titan is running AND logged in, pings healthcheck if so

# Only add the type if it doesn't already exist
if (-not ([System.Management.Automation.PSTypeName]'WinAPI').Type) {
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;

public class WinAPI {
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    
    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    
    [DllImport("user32.dll")]
    public static extern int GetWindowTextLength(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    
    public static List<string> GetWindowTitles(uint processId) {
        var titles = new List<string>();
        EnumWindows((hWnd, lParam) => {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if (pid == processId && IsWindowVisible(hWnd)) {
                int len = GetWindowTextLength(hWnd);
                if (len > 0) {
                    var sb = new StringBuilder(len + 1);
                    GetWindowText(hWnd, sb, sb.Capacity);
                    titles.Add(sb.ToString());
                }
            }
            return true;
        }, IntPtr.Zero);
        return titles;
    }
}
"@
}

$HealthCheckUrl = "https://hc-ping.com/your-uuid-here"

$proc = Get-Process -Name 'Titan' -ErrorAction SilentlyContinue

if (-not $proc) {
    Write-Host "Titan is not running"
    exit 1
}

$titles = [WinAPI]::GetWindowTitles($proc.Id)
$joined = $titles -join '|'

# Check if the window title indicates a logged-in state
if ($joined -like '*System*') {
    try {
        Invoke-WebRequest -Uri $HealthCheckUrl -UseBasicParsing | Out-Null
        Write-Host "Titan logged in - Pinged healthcheck"
        exit 0
    } catch {
        Write-Host "Titan logged in - Failed to ping: $_"
        exit 2
    }
} else {
    Write-Host "Titan running but NOT logged in. Windows: $joined"
    exit 1
}
