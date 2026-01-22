
# Tecom Challenger Protocol

Partially reverse-engineered UDP protocol to control Tecom Titan TS0816 Challenger V8 boards. Data captured via the [Titan software.](https://aritech.com.au/titan-3-5-1-build-31-is-now-available/)

## Overview

This repository contains Node-RED flows and scripts for interacting with Tecom Challenger V8 security panels via UDP on port 3001. The protocol allows for relay control (door lock/unlock) and status polling.

**Note:** This protocol documentation is incomplete. Only the portions that have been reverse-engineered and tested are documented here.

---

## Protocol Basics

### Communication

- **Transport:** UDP
- **Port:** 3001
- **IP:** The IP address of the Challenger panel (e.g., `192.168.1.20`)

### Packet Structure

All packets follow a similar structure:

| Byte(s) | Description |
|---------|-------------|
| 0 | Fixed header: `0x5e` |
| 1 | Varies (observed: `0x70`, `0x60`, `0x40`) |
| 2-3 | Fixed: `0x80 0x00` |
| 4 | Sequence/message counter (increments with each packet) |
| 5-6 | Command identifier |
| 7+ | Command-specific data |
| Last 2 | CRC-16/MODBUS checksum bytes |

### Checksum

The protocol uses CRC-16/MODBUS. The checksum bytes are calculated such that the CRC of the complete packet equals a target value:
- **Lock/Unlock commands:** Target CRC `0x0a43`
- **Status query and time commands:** Target CRC `0x37b1`

---

## Relay Control (Lock/Unlock)

### Command Structure

Lock/unlock commands are 11 bytes:

| Byte | Description |
|------|-------------|
| 0-3 | Header: `5e 70 80 00` |
| 4 | Sequence counter (0x00-0xFF) |
| 5-6 | Command: `03 02` |
| 7 | Action: `0x01` = Lock (normal), `0x02` = Unlock (active) |
| 8 | Door/relay number (1-255) |
| 9-10 | Checksum bytes (calculated to make packet CRC = `0x0a43`) |

### Example Packets

**Lock Door 1:**
```
5e 70 80 00 [seq] 03 02 01 01 [crc1] [crc2]
```

**Unlock Door 1:**
```
5e 70 80 00 [seq] 03 02 02 01 [crc1] [crc2]
```

### Important Notes

- Each command may required two UDP packets to be sent (observed in working implementations)
- The second packet uses command bytes `73 80 00` followed by checksum bytes
- Example pair for Door 1 lock: `5e7080000503020101...` followed by `5e738000...`

---

## Status Polling

### Poll Command Structure

Status query commands are 13 bytes:

| Byte | Description |
|------|-------------|
| 0-3 | Header: `5e 70 80 00` (or `5e 60 80 00`) |
| 4 | Sequence counter |
| 5-6 | Command: `66 04` |
| 7 | Door/relay number |
| 8 | `0x00` |
| 9 | Door/relay number (repeated) |
| 10 | `0x00` |
| 11-12 | Checksum bytes (target CRC = `0x37b1`) |

### Poll Response Format

Responses are 11-13 bytes:

| Byte | Description |
|------|-------------|
| 7 | Door/relay number |
| 9 | State: `0x00` = Locked, `0x01` or `0x02` = Unlocked |

### Live Broadcast Format

When a relay state changes (e.g., from within Titan software), the panel broadcasts a 21-22 byte packet:

| Byte | Description |
|------|-------------|
| 5 | Command identifier: `0x0f` |
| 12 | Door/relay number |
| 18 | State: `0x07` = Locked, `0x04` = Unlocked |

---

## Ping

A simple ping packet can be sent to test connectivity:

```
5e 73 80 00 19 da 82
```

---

## Files

### Node-Red Flows

#### Control Titan Relay.json

Controls door relays via Home Assistant MQTT integration. Contains:
- Pre-configured lock/unlock commands for specific doors
- **Un/lock auto-generator:** A function node that dynamically generates lock/unlock packets for any door number (1-255). This is tested and working.
- **all-in-one status processor:** A function node that processes both poll responses and live broadcasts. Not extensively tested.
- **door xyz - poll:** A function node that generates status poll commands for multiple doors. Not extensively tested.

#### Poll Status of Titan Relays.json

Polls the status of configured relays on a schedule. Contains:
- Pre-configured poll commands for specific doors
- Response parsing to extract relay number and lock state
- MQTT integration for Home Assistant
- Rate limiting (1 message per 3 seconds) to prevent overwhelming the panel

#### Titan Time Sync.json

Encodes and decodes time synchronisation packets. The time encoding scheme:
- Supports years 1990-2053 (hardware limitation)
- Uses a proprietary byte encoding for date and time components

### Scripts

#### tecom_time_setter.ps1

PowerShell script for setting the time on a Challenger panel.

#### Titan_win_checker.ps1

PowerShell script that checks if Titan software is running and logged in, then pings a healthcheck URL.

#### Titan-AutoLoginElevated.ps1

PowerShell script for automatically logging into the Titan software.

---

## Home Assistant Integration

The Node-RED flows integrate with Home Assistant via MQTT using the `ha-mqtt-lock` nodes. Doors appear as lock entities that can be controlled from Home Assistant.

MQTT topics follow the pattern:
- State: `ha-mqtt/lock/Door_X/state`
- Command: `ha-mqtt/lock/Door_X/set`

---

## Limitations and Unknowns

- The full protocol specification is not yet known
- The purpose of byte 1 in packets (varies between `0x70`, `0x60`, `0x40`) is not fully understood
- The second packet in command pairs (`5e738000...`) is observed but its exact purpose is unclear
- Only relay control, relay status polling and on-device time syncing have been reverse-engineered

---

## Dependencies

### Node-RED Modules

- `node-red-contrib-buffer-parser` - For parsing binary UDP data
- `node-red-contrib-ha-mqtt` - For Home Assistant MQTT device integration

---

## Video Guides

Titan Security Software Playlist <br><br>
<a href="https://youtube.com/playlist?list=PLjiGVsNV-rFPJHk_TaN1NEGjwiTmNxulF&si=n2bRCVcKESHVoJCEs">
    <img src="https://img.youtube.com/vi/IPL5BMy9VTc/maxresdefault.jpg" alt="Watch the video" style="width: 50%; border-radius: 8px;">
</a>

---

## Disclaimer

This is an unofficial, reverse-engineered protocol implementation. Use at your own risk. The author is not affiliated with Tecom or Aritech.
