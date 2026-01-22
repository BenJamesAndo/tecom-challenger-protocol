# Titan-AutoLogin.ps1
# Automatically logs into Tecom Titan if on the login screen

param(
    [string]$Username = "YourUsername",
    [string]$Password = "YourPassword"
)

# Check if running as administrator, if not, relaunch as admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Not running as administrator. Relaunching with elevated privileges..."
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Username `"$Username`" -Password `"$Password`""
    Start-Process powershell.exe -Verb RunAs -ArgumentList $args
    exit
}

# Add required types
if (-not ([System.Management.Automation.PSTypeName]'WinFind').Type) {
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class WinFind {
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);
    
    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    
    public static IntPtr FindWindowByTitleAndPid(string title, uint pid) {
        IntPtr result = IntPtr.Zero;
        EnumWindows((hWnd, lParam) => {
            uint wpid;
            GetWindowThreadProcessId(hWnd, out wpid);
            if (wpid == pid && IsWindowVisible(hWnd)) {
                var sb = new StringBuilder(256);
                GetWindowText(hWnd, sb, sb.Capacity);
                if (sb.ToString() == title) {
                    result = hWnd;
                    return false;
                }
            }
            return true;
        }, IntPtr.Zero);
        return result;
    }
}
"@
}

if (-not ([System.Management.Automation.PSTypeName]'KeyHelper').Type) {
Add-Type @"
using System.Runtime.InteropServices;

public class KeyHelper {
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, int dwExtraInfo);
}
"@
}

Add-Type -AssemblyName System.Windows.Forms

# Check if Titan is running
$proc = Get-Process -Name 'Titan' -ErrorAction SilentlyContinue
if (-not $proc) {
    Write-Host "Titan is not running"
    exit 1
}

# Get all window titles for Titan
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

$titles = [WinAPI]::GetWindowTitles($proc.Id)
$allTitles = $titles -join '|'

# Check if already logged in (window title contains "System")
if ($allTitles -like '*System*') {
    Write-Host "Titan is already logged in"
    exit 0
}

# Find the login window (titled just "Titan")
$loginWindow = [WinFind]::FindWindowByTitleAndPid("Titan", $proc.Id)

if ($loginWindow -eq [IntPtr]::Zero) {
    Write-Host "Login window not found"
    exit 1
}

Write-Host "Found Titan login window, attempting auto-login..."

# Use Alt key trick to enable SetForegroundWindow
[KeyHelper]::keybd_event(0x12, 0, 0, 0)  # Alt down
Start-Sleep -Milliseconds 50
$focused = [WinFind]::SetForegroundWindow($loginWindow)
Start-Sleep -Milliseconds 50
[KeyHelper]::keybd_event(0x12, 0, 2, 0)  # Alt up

if (-not $focused) {
    Write-Host "Failed to focus login window"
    exit 2
}

# Wait for window to be ready
Start-Sleep -Milliseconds 800

# Send login credentials
try {
    [System.Windows.Forms.SendKeys]::SendWait($Username)
    [System.Windows.Forms.SendKeys]::SendWait("{TAB}")
    [System.Windows.Forms.SendKeys]::SendWait($Password)
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    
    Write-Host "Login credentials sent successfully"
    
    # Wait for login to complete
    Start-Sleep -Seconds 5
    
    # Re-focus the window in case user clicked away
    [KeyHelper]::keybd_event(0x12, 0, 0, 0)  # Alt down
    Start-Sleep -Milliseconds 50
    [WinFind]::SetForegroundWindow($loginWindow)
    Start-Sleep -Milliseconds 50
    [KeyHelper]::keybd_event(0x12, 0, 2, 0)  # Alt up
    Start-Sleep -Seconds 1
    
    # Open Time Zones editor (E, Z) - Alt already activated the menu
    [System.Windows.Forms.SendKeys]::SendWait("e")
    Start-Sleep -Seconds 1
    [System.Windows.Forms.SendKeys]::SendWait("z")
    
    Write-Host "Opened Time Zones editor"
    exit 0
} catch {
    Write-Host "Failed to send login: $_"
    exit 3
}
