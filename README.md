# monitor-switch

Make your monitors' inputs follow a dumb USB switch, on Windows.

If you share one keyboard and mouse between two PCs with a cheap USB switch
(Benfei and friends), pressing its button moves the peripherals but leaves both
monitors showing the wrong machine. This watcher fixes that: press the button,
and the monitors follow.

It also documents, with measurements, **exactly which parts of this are
impossible** — because a lot of monitors lie about what they support, and working
that out took far longer than writing the script. See
[docs/FINDINGS.md](docs/FINDINGS.md).

## What it does

The USB switch has no software interface — nothing can ask it which PC it points
at. So the shared peripherals themselves are used as the signal: if your mouse
and keyboard are present on this PC, the switch points here; if they vanish, it
points at the other machine. On each transition the watcher writes the monitors'
input-select register over DDC/CI.

One press of the button, ~190 ms later the picture follows.

## What works, and what doesn't

Measured on an AOC Q27G2G4 and an LG UltraGear 27GN800-B:

| Situation | Standard monitor (AOC) | LG with the `0xF4` quirk |
|---|---|---|
| Button press → other PC | automatic | automatic |
| Button press → back to this PC | automatic | **not possible** |
| Other PC sleeps/disconnects | automatic | automatic (panel's own auto-input) |

The one hole is reclaiming an LG-style panel on a button press while the other
machine is still driving it. That is not a missing feature in this tool — such
panels **stop answering DDC entirely on any input they are not currently
displaying**, so there is nothing to send a command to. Even a brightness read
fails. Eleven input codes, the raw NVAPI sidechannel, and a DisplayPort hot-plug
with Auto Input Switch enabled were all tried; the full evidence is in
[docs/FINDINGS.md](docs/FINDINGS.md).

If you need that last case automated, it takes hardware that interrupts the other
machine's video cable — options and costs in [docs/HARDWARE.md](docs/HARDWARE.md).

## Requirements

- Windows 10/11 x64
- Both PCs cabled to each monitor on **different inputs** (e.g. DisplayPort from
  one, HDMI from the other)
- Monitors supporting DDC/CI (enable it in the OSD if there is a toggle)
- [ControlMyMonitor](https://www.nirsoft.net/utils/control_my_monitor.html)
- **Only for LG panels that ignore `VCP 0x60`:**
  [deskmux](https://github.com/klaidliadon/deskmux) and an **NVIDIA** GPU
  driving the monitor
- No admin rights needed

See [tools/README.md](tools/README.md) for downloads and checksums. The tools are
not vendored here.

## Setup

### 1. Install the tools

Download ControlMyMonitor (and deskmux if you have an affected LG) and note the
paths. The shipped config assumes `D:\Monitor\controlmymonitor\` and
`D:\Monitor\deskmux\`.

### 2. Find your monitor IDs and input codes

```powershell
cd scripts
.\discover.ps1
```

This prints each monitor's **Short Monitor ID** (use that, not `\\.\DISPLAYn` —
the numbering shifts) and its `Input Select` register with the input codes the
panel admits to having. Common codes: `15` = DisplayPort1, `16` = DisplayPort2,
`17` = HDMI1, `18` = HDMI2.

**Verify which code is which physical port** rather than assuming. Switch a
monitor by hand and read the value back, or set a value and look at the screen.
Guessing here cost real time: a monitor reported `17` while still displaying
DisplayPort, because `17` was an empty port it had silently refused to select.

### 3. Find the devices that move with the switch

```powershell
.\discover.ps1 -WatchDevices
```

Press the switch button during the countdown, wait a few seconds, press it
again. The script reports the VID/PID pairs that appeared and disappeared —
those are your shared peripherals.

### 4. Configure

Edit the `CONFIG` block at the top of `scripts/watch-usb-switch.ps1`:

```powershell
$watchedDevices = @('VID_1038&PID_185A', 'VID_1E7D&PID_2FEE')

$stdMonitor = "AOC2702"   # Short Monitor ID
$stdHere    = 15          # this PC's input
$stdAway    = 18          # the other PC's input

$lgModel    = "GN800"     # "" to disable LG handling entirely
$lgAway      = "hdmi1"    # the other PC's input on the LG
```

If your monitors all switch fine with ControlMyMonitor, set `$lgModel = ""` and
ignore deskmux completely.

### 5. Test it before installing

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\watch-usb-switch.ps1
```

Press the button both ways and watch `scripts/switch.log`:

```
2026-10-10 12:52:50  -> other PC: AOC2702 to 18, LG to hdmi1 (186ms)
2026-10-10 12:53:02  -> this PC: AOC2702 to 15 (5ms)
```

### 6. Install at logon

Edit the script path inside `scripts/launch-watcher.vbs`, then drop a copy into
your Startup folder:

```powershell
Copy-Item .\launch-watcher.vbs "$([Environment]::GetFolderPath('Startup'))\"
```

Run it once to start without logging out:

```powershell
wscript.exe .\launch-watcher.vbs
```

It runs hidden. Task Scheduler works too, but registering a task needs
elevation; the Startup folder does not.

### 7. Enable Auto Input Switch in each monitor's OSD

This is what makes a panel come back on its own when the other machine sleeps or
is unplugged — the one case the software cannot cover for LG-style panels.

## Configuration reference

| Setting | Meaning |
|---|---|
| `$cmm`, `$deskmux` | Tool paths |
| `$watchedDevices` | VID/PID fragments matched against `InstanceId` |
| `$stdMonitor` | Short Monitor ID of the DDC-standard monitor |
| `$stdHere` / `$stdAway` | `VCP 0x60` values for this PC / the other PC |
| `$lgModel` | deskmux capability model string; `""` disables LG handling |
| `$lgAway` | deskmux input name for the other PC |
| `$lgFast` | `-fast` (~214 ms vs ~1200 ms); verify per machine |
| `$pollMs` | Poll interval; detection itself costs ~260 ms |

## Troubleshooting

**Nothing happens at all.** Check `switch.log` exists and shows
`watcher started`. If there is no log, the script is not running — start it in a
visible console to see the error.

**The log shows switches but the picture doesn't change.** The monitor is
accepting writes and ignoring them. Confirm DDC works at all by changing
brightness over DDC; if brightness moves but input doesn't, you have the LG
problem — see [docs/FINDINGS.md](docs/FINDINGS.md).

**It switches to a black screen.** The configured code points at an input with
nothing on it. Re-check step 2.

**The LG switches away but never comes back.** Expected. See the table above.

**It switches the wrong monitor.** deskmux indices are renumbered whenever a
display is enabled or disabled. The watcher resolves by model string at startup
to avoid this; restart it after changing your display layout.

**Writing values by hand from Git Bash does nothing.** Git Bash mangles `/flag`
arguments and `\\.\DISPLAYn\Monitor0` strings. Use `MSYS_NO_PATHCONV=1` or a
`.bat` file. This one produced a completely wrong conclusion during development.

## Credits

- [ControlMyMonitor](https://www.nirsoft.net/utils/control_my_monitor.html) and
  [MultiMonitorTool](https://www.nirsoft.net/utils/multi_monitor_tool.html) by Nir Sofer
- [deskmux](https://github.com/klaidliadon/deskmux) by klaidliadon — the LG
  sidechannel implementation this depends on
- [ddcutil](https://github.com/rockowitz/ddcutil)'s
  [LG input source wiki](https://github.com/rockowitz/ddcutil/wiki/Switching-input-source-on-LG-monitors)
  for the `0xF4` value table
- [display-switch](https://github.com/haimgel/display-switch) — a maintained,
  cross-platform tool for the same use case, if you want something less
  hand-rolled (standard DDC only, so it cannot drive the LG sidechannel)

## Licence

MIT — see [LICENSE](LICENSE).
