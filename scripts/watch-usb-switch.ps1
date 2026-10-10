# Makes monitor inputs follow a dumb USB switch.
#
# A passive USB switch (Benfei and similar) moves the shared keyboard/mouse
# between two PCs and exposes no software signal of its own. This watcher uses
# the peripherals themselves as the tell: present on this PC means the switch
# points here, absent means it points at the other machine. On each transition
# it drives the monitors' input-select registers over DDC/CI so the picture
# follows the keyboard.
#
# Run it on the PC that should own the displays by default. See README.md for
# how to discover the values in the CONFIG block, and docs/FINDINGS.md for why
# the pieces are shaped the way they are.

#region CONFIG ---------------------------------------------------------------

# Tools. ControlMyMonitor drives standard DDC; deskmux is only needed for LG
# panels that ignore the standard input register (see docs/FINDINGS.md).
$cmm     = "D:\Monitor\controlmymonitor\ControlMyMonitor.exe"
$deskmux = "D:\Monitor\deskmux\deskmux.exe"
$log     = "$PSScriptRoot\switch.log"

# USB devices that physically move with the switch. Discover with
# scripts/discover.ps1 -WatchDevices. Matched against InstanceId, so the
# VID/PID pair is enough.
$watchedDevices = @(
    'VID_1038&PID_185A',   # SteelSeries Aerox 9 Wireless (mouse receiver)
    'VID_1E7D&PID_2FEE'    # ROCCAT keyboard
)

# Monitor driven over standard DDC (VCP 0x60). Addressed by Short Monitor ID,
# which is stable across machines -- unlike \\.\DISPLAYn numbering.
$stdMonitor = "AOC2702"    # AOC Q27G2G4
$stdHere    = 15           # 0x0F DisplayPort -> this PC
$stdAway    = 18           # 0x12 HDMI2       -> other PC

# Monitor driven over the LG service sidechannel (VCP 0xF4 @ source 0x50).
# Leave $lgModel empty to disable LG handling entirely.
$lgModel    = "GN800"      # matched against deskmux's capabilities string
$lgAway     = "hdmi1"      # target when handing over; see deskmux config
$lgFast     = $true        # -fast: ~214ms instead of ~1200ms, verify per machine

# Poll interval. The detection query itself costs ~260ms, so this is roughly
# half the end-to-end latency.
$pollMs     = 250

#endregion -------------------------------------------------------------------

$deviceFilter = ($watchedDevices | ForEach-Object { "DeviceID LIKE 'USB%$_%'" }) -join ' OR '

function Write-Log($msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg" | Add-Content -Path $log
}

function Test-PeripheralsPresent {
    # Win32_PnPEntity with a WQL filter rather than Get-PnpDevice: ~260ms vs
    # ~450ms, and it works without the optional PnpDevice module.
    return [bool](Get-CimInstance Win32_PnPEntity -Filter $deviceFilter -ErrorAction SilentlyContinue)
}

function Set-StdMonitorInput($value) {
    # ControlMyMonitor is a GUI-subsystem binary: PowerShell neither waits for
    # it nor sets $LASTEXITCODE. Launched without -Wait on purpose so this
    # overlaps the LG write instead of adding ~1s to it.
    Start-Process -FilePath $cmm -ArgumentList '/SetValue', $stdMonitor, '60', "$value"
}

function Resolve-LgIndex {
    # deskmux addresses monitors by index and renumbers them whenever a display
    # is enabled or disabled, so the index must be discovered rather than
    # assumed. Each probe is a DDC round trip (~3s), which is why this runs
    # once at startup and not per switch.
    #
    # The model string arrives over DDC, so the LG is only identifiable while
    # its input from this PC is the active one.
    if (-not $lgModel) { return $null }
    foreach ($i in 0..3) {
        $caps = & $deskmux -m $i probe 2>&1
        if ($caps -match "model\($lgModel\)") { return $i }
    }
    return $null
}

function Set-LgInput($index, $target) {
    # Not $args -- that is an automatic variable inside a function.
    $dmArgs = @()
    if ($lgFast) { $dmArgs += '-fast' }
    $dmArgs += @('-m', "$index", 'input', $target)
    & $deskmux @dmArgs *>$null
}

Write-Log "watcher started (pid $PID)"

$lgIndex = Resolve-LgIndex
if ($lgModel) {
    if ($null -eq $lgIndex) {
        Write-Log "LG ($lgModel) not resolved -- only visible while its input from this PC is active"
    } else {
        Write-Log "LG ($lgModel) resolved to deskmux index $lgIndex"
    }
}

$prev = Test-PeripheralsPresent
Write-Log "initial state: peripherals $(if ($prev) { 'present' } else { 'absent' })"

while ($true) {
    Start-Sleep -Milliseconds $pollMs

    $now = Test-PeripheralsPresent
    if ($now -eq $prev) { continue }
    $prev = $now

    $sw = [Diagnostics.Stopwatch]::StartNew()

    if ($now) {
        # Claiming the displays back. The LG is deliberately not touched: once
        # the other PC owns it, it stops answering DDC on this PC's connector
        # altogether, so there is nothing to send a command to. It returns on
        # its own only if the other machine's signal dies. See docs/FINDINGS.md.
        Set-StdMonitorInput $stdHere
        Write-Log "-> this PC: $stdMonitor to $stdHere ($($sw.ElapsedMilliseconds)ms)"
    } else {
        # Handing the displays over. This works for the LG because its input
        # from this PC is still the active one at this moment -- it can be
        # pushed away, never pulled back.
        Set-StdMonitorInput $stdAway
        if ($null -ne $lgIndex) { Set-LgInput $lgIndex $lgAway }
        Write-Log "-> other PC: $stdMonitor to $stdAway, LG to $lgAway ($($sw.ElapsedMilliseconds)ms)"
    }
}
