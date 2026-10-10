# Findings

Everything below was measured on the hardware listed in [Test setup](#test-setup),
not inferred from documentation. Where a conclusion was wrong at first, the
correction is kept rather than quietly edited out — the wrong turns are the
useful part if you are debugging the same thing.

## Summary

| Direction | AOC Q27G2G4 | LG UltraGear 27GN800-B |
|---|---|---|
| Hand over to the other PC (button press) | automatic | automatic |
| Reclaim on button press, other PC still running | automatic | **impossible from this PC** |
| Reclaim after the other PC sleeps/disconnects | automatic | automatic (panel's own auto-input) |

Two of three cases work on both panels. The one hole is reclaiming the LG while
the other machine keeps driving it, and it is a property of the panel's
firmware, not something a tool can route around.

## The two LG problems, which are separate

They compound, and conflating them wastes time.

### 1. Input selection is not on the standard register

The LG advertises `VCP 0x60` (Input Select) in its capability string — reporting
possible values `17, 18, 15, 16` — and then silently discards every write. The
write returns success and the register read-back never changes:

```
SetValue 0x60 = 17  -> ok, no error
GetValue 0x60       -> 15      (unchanged, and unchanged 3s later)
```

Brightness (`0x10`) on the same channel, same process, seconds apart, works
fine — so this is not permissions, cabling, or a conflicting application.

LG moved input selection to a service sidechannel: **`VCP 0xF4` sent with DDC
source address `0x50`** ("DDC2AB") instead of the standard `0x51`. Windows'
`dxva2.dll` hardcodes `0x51` with no override, which is why ControlMyMonitor,
Twinkle Tray and every other conventional Windows tool fail here — they all end
up in the same `SetVCPFeature` call.

Reaching it needs raw I²C through the GPU driver. [`deskmux`](https://github.com/klaidliadon/deskmux)
does this via `NvAPI_I2CWrite` on NVIDIA. Values on that channel:

| Input | Value |
|---|---|
| HDMI 1 | `0x90` |
| HDMI 2 | `0x91` |
| DisplayPort 1 | `0xD0` |
| DisplayPort 2 | `0xD1` |
| USB-C | `0xD2` |
| Auto | `0x00` |

`0x90` was confirmed working on the 27GN800-B, so this panel does use the
documented mapping. **This problem is solved** — handover to the other PC works.

### 2. The panel only services its selected input

This is the one that cannot be worked around. While the LG displays the other
machine, it stops answering DDC on this PC's DisplayPort connector entirely:

```
# LG showing the other PC, reading over this PC's DisplayPort link:
get 0x10  -> error: GetVCPFeatureAndVCPFeatureReply(0x10):
             a DDC/CI message had an invalid value in its command field
             (4 consecutive attempts, while the AOC on the same GPU reads fine)

# the same read, moments after DisplayPort becomes the selected input again:
get 0x10  -> current=86
```

It is not specific to input commands — a plain brightness *read* fails. There is
nothing listening, so no command of any kind can arrive. Eleven input codes were
tried on the sidechannel while the panel was on the other PC, all with no
effect: `0xD0`, `0xC0`, `0xE0`, `0xD1`, `0x00`, `0xD2`, `0x0F`, `0x10`, `0xB0`,
`0xA0`, `0xF0`.

**Beware the success counter.** `deskmux input` reports how many writes the bus
accepted (`27/28` here), and that number is **identical** whether the panel obeys
or ignores the command — it only means the GPU clocked bytes onto the wire. The
sidechannel never acknowledges. The only confirmation is the screen changing.

The AOC behaves the opposite way: it keeps its DDC engine answering on every
connected input, which is exactly why it can pull itself back. Nothing in either
OSD configures this; it is a vendor firmware choice, and the MCCS spec does not
require servicing idle inputs.

This matches reports from others — the ddcutil wiki notes some monitors
*"only listen to DDC commands on the active input"*, and a
[BetterDisplay discussion](https://github.com/waydabber/BetterDisplay/discussions/4246)
describes the same dead end on an LG: *"any commands from the PC to try to swap
it back doesn't do anything"*. No workaround is offered by the people who
reverse-engineered the protocol.

## What does bring the LG back

With **Auto Input Switch enabled** in the LG's OSD, the panel returns to
DisplayPort on its own when the other machine's signal dies — verified by
polling DDC reachability as a proxy for the selected input:

```
12:50:41  LG NOT on DisplayPort (other PC)
12:51:48  LG on DisplayPort          <- other machine slept; no commands sent
```

Note the asymmetry, which is easy to misread as a contradiction:

- **Active signal disappears** → the panel rescans and switches. Works.
- **New signal appears** → the panel refuses to abandon a live input. Does not work.

So hot-plugging this PC's DisplayPort output (disable/re-enable the display,
forcing a fresh signal) does **not** reclaim it, even with Auto Input Switch on.
Tested; no effect. Only killing the *other* machine's signal works, which is why
the remaining hardware options in [HARDWARE.md](HARDWARE.md) all amount to
interrupting that cable.

## Latency

Measured per step, which mattered because the first working version took ~12.5s
end to end:

| Step | Cost |
|---|---|
| `deskmux probe` (one monitor) | 3056 ms |
| resolving the LG index by probing 0..3 | **8773 ms** |
| `deskmux input` full sweep | 1203 ms |
| `deskmux input -fast` | **214 ms** |
| ControlMyMonitor `/SetValue` | 1071 ms |
| `Get-PnpDevice -Class … -Status OK` | 451 ms |
| `Get-CimInstance Win32_PnPEntity` + WQL filter | **263 ms** |

Resolving the index on every switch dominated everything. Moving it to startup,
adding `-fast`, switching to the WQL filter and firing the ControlMyMonitor call
without `-Wait` (so both monitors move in parallel) brought a handover to
**186 ms**, and reclaiming the AOC to **6 ms**.

`-fast` sends only the per-output-bit writes instead of sweeping every display
mask. deskmux's author notes it needs per-machine verification; it is confirmed
working here, and `$lgFast = $false` reverts it.

## Implementation traps

All of these fail *silently* — they look like success while doing nothing.

- **Git Bash mangles arguments** to Windows executables: a leading `/flag` gets
  path-converted, and `\\.\DISPLAY2\Monitor0` gets mangled. This made a
  `/SetValue` call a no-op, which was initially misread as the monitor refusing
  the command, producing a confident but wrong conclusion that monitors only obey
  the PC that currently owns the picture. It was caught when the same command
  worked from a `.bat` file. Use `MSYS_NO_PATHCONV=1`, or put commands in a batch
  file.
- **`Get-PnpDevice` fails silently inside `Register-WmiEvent -Action` blocks.**
  It comes from an optional module that is not auto-loaded in the event runspace,
  so the handler dies before doing anything — with no error anywhere. `$using:`
  variables do not work in those blocks either. Hence polling in the main script
  body rather than event subscriptions.
- **`ControlMyMonitor.exe` is a GUI-subsystem binary**, so PowerShell's call
  operator neither waits for it nor sets `$LASTEXITCODE`. Use
  `Start-Process -Wait` when the result matters.
- **`deskmux` monitor indices are renumbered** whenever a display is enabled or
  disabled. After a hot-plug test, `-m 1` silently became a different panel —
  caught only because the brightness read returned the wrong monitor's value.
  Resolve by model string instead of trusting an index.
- **Register read-back can lie.** The AOC reported input `17` while still
  displaying DisplayPort, after being told to switch to an empty port. Treat the
  screen as the only source of truth.
- **Killing processes by matching `CommandLine`** also matches the querying
  PowerShell process itself, killing the shell mid-command. Exclude `$PID`.

## A correction worth repeating

Mid-investigation the conclusion was "the LG's DisplayPort connector is dead
while inactive, proven by a failed brightness write". That reasoning was too
quick: deskmux's README documents that a panel's DDC engine can **wedge** after
certain writes and then fail every read until power-cycled, and dozens of writes
had just been sent. A single failure could not distinguish "unreachable" from
"wedged".

It took repeated reads, at the *correct* index, with a known-good control (the
AOC reading fine on the same GPU at the same moment) to establish it properly.
The conclusion survived — but only the second version of it was actually
evidence.

## Test setup

- Windows 11 Pro 26200, NVIDIA GeForce RTX 4070 Ti SUPER
- Gaming PC on DisplayPort to both monitors; laptop on HDMI to both
- **AOC Q27G2G4** (`AOC2702`, DDC model `CQ27G2U`) — laptop on HDMI2
- **LG UltraGear 27GN800-B** (`GSM5BB4`, DDC model `GN800`, MCCS 2.1) — laptop on HDMI1
- Dell P2422H present but not part of the switching
- **BENFEI USB 3.0 Switch** — passive, button-only, no software control channel
- ControlMyMonitor 1.43, deskmux 0.3.2, MultiMonitorTool

## References

- [ddcutil: switching input source on LG monitors](https://github.com/rockowitz/ddcutil/wiki/Switching-input-source-on-LG-monitors) — the `0xF4` / `0x50` value table
- [deskmux](https://github.com/klaidliadon/deskmux) — raw NVAPI I²C on Windows
- [BetterDisplay #4246](https://github.com/waydabber/BetterDisplay/discussions/4246) — same reclaim dead end on LG
- [display-switch](https://github.com/haimgel/display-switch) — maintained tool for the same use case, standard DDC only
