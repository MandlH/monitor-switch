# Closing the remaining gap with hardware

One case cannot be automated in software: reclaiming an LG-style panel (one that
only services its selected input) on a button press, while the other machine is
still driving it. See [FINDINGS.md](FINDINGS.md) for the measurements.

The panel *does* come back on its own when the other machine's signal dies, so
every option below works the same way — **interrupt that video cable** and let
the monitor's own Auto Input Switch do the rest. None of them require software on
the other machine.

## Option 1 — USB display adapter on the switch

Run the other machine's feed to that monitor through a USB display adapter
(DisplayLink-class) plugged into the USB switch's shared ports.

Pressing the button physically disconnects the adapter from that machine, its
video output dies, and the panel falls back to you. The handover direction keeps
working as it already does.

- **Cost:** ~€35–60
- **Pros:** the button you already press does everything; no extra software, no
  extra actions, no soldering
- **Cons:** that output runs through compression — fine for a laptop, not for
  gaming. The panel may show "no signal" for a few seconds when switching *to*
  the other machine while the adapter initialises; add a delay before the push if
  that bothers you.

## Option 2 — Smart plug feeding a powered HDMI splitter

Put a powered HDMI splitter in the other machine's path to that monitor, and a
smart plug on the splitter. When your peripherals return, the watcher cuts power
for a few seconds, the panel heals, and power is restored.

- **Cost:** ~€25
- **Pros:** fully automatic; no change to how either machine drives video
- **Cons:** more moving parts than the job deserves, and a few seconds of
  blackout on every switch

## Option 3 — Dual-monitor KVM switch

Replace the USB switch with a KVM that switches video *and* USB in hardware.

- **Cost:** ~€100–200
- **Pros:** the clean answer. Never needs the panels' cooperation, so it removes
  the LG problem, the scripting, and the DDC quirks in one go
- **Cons:** cost; and for high-refresh gaming check the model's bandwidth
  (DisplayPort version, refresh rate at your resolution) before buying

## Option 4 — USB relay across the switch's button

If your USB switch has a wired remote button, that remote is just a momentary
contact. A USB relay board wired in parallel lets software "press" it.

Note this only moves USB — it does **not** help the LG, which needs the other
machine's video killed. It solves a different problem: having the switch itself
flip automatically, for example when the other machine disconnects (which this PC
can detect by watching the monitors return over DDC).

- **Cost:** ~€10 plus soldering
- **Cons:** poor value for saving a single button press, and it does nothing for
  the video side

## What to look for when buying

The behaviours that matter here are never on a spec sheet, and they do not track
price or panel quality — the better gaming monitor was the worse one for this job.
The rough signal is marketing that mentions **KVM** or **auto input switching**,
since those features force a vendor to get multi-input DDC behaviour right.

For switches, **auto-fallback on host power loss** is the feature that makes a
switch follow a machine disconnecting. It is not standard, so confirm a specific
model advertises it rather than assuming.
