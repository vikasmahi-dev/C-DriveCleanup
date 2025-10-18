
# DiskCleanup.ps1
# Run as Administrator

# --- Configuration ---
$LogFile = "C:\DiskCleanup\cleanup_log.txt"
$DaysToKeep = 30  # Retention for IIS logs
$DryRun = $false  # Set to $true for WhatIf mode

# --- Logging Function ---
function Log {
    param([string]$Message)
    Add-Content -Path $LogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
}

# --- Admin Check ---
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Please run this script as Administrator." -ForegroundColor Red
    exit
}

# --- Create Log Directory ---
if (-not (Test-Path -Path (Split-Path $LogFile))) {
    New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null
}

Write-Host "Starting Disk Cleanup..." -ForegroundColor Cyan
Log "Starting Disk Cleanup..."

# --- Confirmation Prompt ---
$confirm = Read-Host "This will delete system and temp files. Continue? (Y/N)"
if ($confirm -ne 'Y') {
    Write-Host "Cleanup aborted." -ForegroundColor Yellow
    Log "Cleanup aborted by user."
    exit
}

# --- 1. Windows Update Cache ---
Write-Host "`n[1/5] Cleaning SoftwareDistribution..."
Log "Cleaning SoftwareDistribution..."
try {
    Stop-Service wuauserv -Force
    Stop-Service bits -Force
    Remove-Item -Path "C:\Windows\SoftwareDistribution\*" -Recurse -Force -ErrorAction Stop
    Start-Service wuauserv
    Start-Service bits
    Log "SoftwareDistribution cleaned successfully."
} catch {
    Log "Error cleaning SoftwareDistribution: $_"
}

# --- 2. Temp Files ---
Write-Host "`n[2/5] Cleaning Temp files..."
Log "Cleaning Temp files..."
try {
    if ($DryRun) {
        Remove-Item -Path "$env:TEMP\*" -Recurse -Force -WhatIf
        Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -WhatIf
    } else {
        Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction Stop
        Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction Stop
    }
    Log "Temp files cleaned successfully."
} catch {
    Log "Error cleaning Temp files: $_"
}

# --- 3. IIS Logs ---
$LogPath = "C:\inetpub\logs\LogFiles"
Write-Host "`n[3/5] Cleaning IIS Logs older than $DaysToKeep days..."
Log "Cleaning IIS Logs older than $DaysToKeep days..."
if (Test-Path $LogPath) {
    try {
        Get-ChildItem -Path $LogPath -Recurse -Include *.log |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$DaysToKeep) } |
            ForEach-Object {
                if ($DryRun) {
                    Write-Host "Would delete: $($_.FullName)"
                } else {
                    Remove-Item $_.FullName -Force -ErrorAction Stop
                }
            }
        Log "IIS logs cleanup completed."
    } catch {
        Log "Error cleaning IIS logs: $_"
    }
} else {
    Write-Host "IIS Log path not found, skipping..."
    Log "IIS Log path not found, skipped."
}

# --- 4. Recycle Bin ---
Write-Host "`n[4/5] Emptying Recycle Bin..."
Log "Emptying Recycle Bin..."
try {
    if (-not $DryRun) {
        (New-Object -ComObject Shell.Application).NameSpace(0xA).Items() |
            ForEach-Object { Remove-Item $_.Path -Recurse -Force -ErrorAction SilentlyContinue }
    } else {
        Write-Host "Dry run: Recycle Bin would be emptied."
    }
    Log "Recycle Bin emptied."
} catch {
    Log "Error emptying Recycle Bin: $_"
}

# --- 5. DISM Component Store ---
Write-Host "`n[5/5] Running DISM Component Cleanup (this may take a while)..."
Log "Running DISM Component Cleanup..."
try {
    if (-not $DryRun) {
        Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
    } else {
        Write-Host "Dry run: DISM cleanup would be executed."
    }
    Log "DISM cleanup completed."
} catch {
    Log "Error running DISM cleanup: $_"
}

Write-Host "`nDisk Cleanup Completed Successfully!" -ForegroundColor Green
Log "Disk Cleanup Completed Successfully."
