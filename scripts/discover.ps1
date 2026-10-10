# Finds the values needed for the CONFIG block in watch-usb-switch.ps1.
#
#   .\discover.ps1                  # monitors + DDC input registers + deskmux indices
#   .\discover.ps1 -WatchDevices    # identify which USB devices move with the switch
#
# Nothing here writes to the hardware; it only reads.

[CmdletBinding()]
param(
    [switch]$WatchDevices,
    [int]$Seconds = 30,
    [string]$Cmm     = "D:\Monitor\controlmymonitor\ControlMyMonitor.exe",
    [string]$Deskmux = "D:\Monitor\deskmux\deskmux.exe"
)

function Get-MonitorList {
    # Returns one object per real display. Enumerating is necessary because
    # ControlMyMonitor silently falls back to the primary monitor when handed a
    # \\.\DISPLAYn that does not exist, which looks like a duplicate result.
    if (-not (Test-Path $Cmm)) { Write-Warning "ControlMyMonitor not found at $Cmm"; return @() }

    $tmp = Join-Path $env:TEMP "cmm-monitors.txt"
    Start-Process -FilePath $Cmm -ArgumentList '/smonitors', $tmp -Wait
    if (-not (Test-Path $tmp)) { return @() }

    $monitors = @()
    $current = $null
    foreach ($line in (Get-Content $tmp -Encoding Unicode)) {
        switch -Regex ($line) {
            'Monitor Device Name:\s*"(.+)"' {
                if ($current) { $monitors += $current }
                $current = [pscustomobject]@{ Device = $Matches[1]; Name = ''; ShortId = '' }
            }
            'Monitor Name:\s*"(.*)"'        { if ($current) { $current.Name    = $Matches[1] } }
            'Short Monitor ID:\s*"(.*)"'    { if ($current) { $current.ShortId = $Matches[1] } }
        }
    }
    if ($current) { $monitors += $current }
    Remove-Item $tmp -ErrorAction SilentlyContinue
    return $monitors
}

function Show-Monitors($monitors) {
    Write-Host "`n=== Monitors (use 'Short Monitor ID' in CONFIG) ===" -ForegroundColor Cyan
    foreach ($m in $monitors) {
        Write-Host ("  {0,-24} {1,-16} {2}" -f $m.Device, $m.ShortId, $m.Name)
    }
}

function Show-InputRegisters($monitors) {
    Write-Host "`n=== Input Select (VCP 0x60) per monitor ===" -ForegroundColor Cyan
    Write-Host "'Possible Values' lists the inputs the panel admits to having."
    Write-Host "Common codes: 15=DisplayPort1 16=DisplayPort2 17=HDMI1 18=HDMI2`n"
    if (-not (Test-Path $Cmm)) { return }

    $i = 0
    foreach ($m in $monitors) {
        $csv = Join-Path $env:TEMP "cmm-input-$i.csv"
        $i++
        Start-Process -FilePath $Cmm -ArgumentList '/scomma', $csv, $m.ShortId -Wait
        if (-not (Test-Path $csv)) { continue }

        $row = Get-Content $csv -Encoding Unicode | Where-Object { $_ -like '60,*' }
        if ($row) { Write-Host ("  {0,-16} {1}" -f $m.ShortId, $row) }
        else      { Write-Host ("  {0,-16} no readable Input Select register" -f $m.ShortId) }
        Remove-Item $csv -ErrorAction SilentlyContinue
    }

    Write-Host "`nIf a monitor accepts a write to 0x60 but the picture never changes,"
    Write-Host "it is probably an LG using the 0xF4 sidechannel -- see docs/FINDINGS.md."
}

function Show-DeskmuxIndices {
    Write-Host "`n=== deskmux monitor indices (for the LG sidechannel) ===" -ForegroundColor Cyan
    if (-not (Test-Path $Deskmux)) { Write-Warning "deskmux not found at $Deskmux"; return }
    Write-Host "Indices are renumbered when displays are enabled/disabled, so the"
    Write-Host "watcher resolves them by model string at startup rather than hardcoding.`n"

    foreach ($i in 0..3) {
        $caps  = & $Deskmux -m $i probe 2>&1
        $model = [regex]::Match(($caps -join ' '), 'model\(([A-Za-z0-9]+)\)').Groups[1].Value
        if ($model) { Write-Host ("  -m {0}  model({1})" -f $i, $model) }
        else        { Write-Host ("  -m {0}  unreachable (not this PC's active input, or no such display)" -f $i) }
    }
}

function Watch-Devices {
    Write-Host "`n=== Identifying devices that move with the switch ===" -ForegroundColor Cyan
    Write-Host "Press the USB switch button to send the peripherals to the OTHER PC,"
    Write-Host "wait a few seconds, then press it again to bring them back."
    Write-Host "Watching for $Seconds seconds...`n"

    $seen = @{}
    $samples = 0
    $deadline = (Get-Date).AddSeconds($Seconds)

    while ((Get-Date) -lt $deadline) {
        $ids = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
               Where-Object { $_.DeviceID -like 'USB\*' } |
               Select-Object -ExpandProperty DeviceID
        foreach ($id in $ids) { $seen[$id] = ($seen[$id] + 1) }
        $samples++
        Start-Sleep -Seconds 1
    }

    # Anything not present in every sample came or went while we watched, which
    # is exactly what the switch does to the shared peripherals.
    $changed = $seen.GetEnumerator() | Where-Object { $_.Value -ne $samples }

    if (-not $changed) {
        Write-Host "No USB devices changed state. Was the button pressed?" -ForegroundColor Yellow
        return
    }

    Write-Host "These devices appeared/disappeared -- the VID/PID pairs go in `$watchedDevices:`n"
    $changed |
        ForEach-Object { [regex]::Match($_.Key, 'VID_[0-9A-F]{4}&PID_[0-9A-F]{4}').Value } |
        Where-Object { $_ } |
        Group-Object |
        Sort-Object Count -Descending |
        ForEach-Object { Write-Host ("  {0}   ({1} device nodes)" -f $_.Name, $_.Count) }
}

if ($WatchDevices) {
    Watch-Devices
} else {
    $monitors = Get-MonitorList
    Show-Monitors $monitors
    Show-InputRegisters $monitors
    Show-DeskmuxIndices
    Write-Host "`nRun '.\discover.ps1 -WatchDevices' to identify the switched peripherals.`n"
}
