# Third-party tools

These are **not** committed to this repository — they have their own licences and
are not mine to redistribute. Download them yourself and point the `CONFIG`
block in `scripts/watch-usb-switch.ps1` at wherever you put them.

The paths in the shipped config assume `D:\Monitor\<tool>\`.

## ControlMyMonitor (required)

Drives standard DDC/CI input switching (`VCP 0x60`) for monitors that implement
it properly.

- Source: <https://www.nirsoft.net/utils/control_my_monitor.html>
- Freeware, by Nir Sofer
- Version used here: 1.43

Note `/GetValue` returns the value as the process exit code, which is why the
helper scripts read it via `%errorlevel%` in a batch file rather than from
stdout.

## deskmux (only for LG panels that ignore `VCP 0x60`)

Sends the LG service sidechannel (`VCP 0xF4` at DDC source address `0x50`) using
raw I²C through `NvAPI_I2CWrite`. Needed because Windows' `dxva2.dll` hardcodes
source address `0x51`, so no conventional tool can reach that channel.

- Source: <https://github.com/klaidliadon/deskmux>
- Version used here: v0.3.2
- **Requires an NVIDIA GPU driving the monitor.** AMD users want
  [amdddc-windows](https://github.com/amildahl/amdddc-windows) or
  [LGInputSwitch](https://github.com/phillip9933/LGInputSwitch), which do the
  same thing through AMD's ADL.

Binaries are unsigned, so SmartScreen warns on first run. Verify the download
against the published `checksums.txt`:

```powershell
(Get-FileHash -Algorithm SHA256 .\deskmux_0.3.2_windows_amd64.zip).Hash.ToLower()
# expected: 1a7e902ae36eafcfeadf76ba7179efcaaa4ba3b40903d573cb056474a067abb0
```

That checksum verifies download integrity only — it ships from the same place as
the binary, so it is not independent proof of authenticity.

If your monitor switches fine with ControlMyMonitor alone, you do not need this:
set `$lgModel = ""` in the config to skip LG handling entirely.

## MultiMonitorTool (optional, diagnostics only)

Enables/disables individual displays, which is how the DisplayPort hot-plug test
in [FINDINGS.md](../docs/FINDINGS.md) was performed. Not used by the watcher.

- Source: <https://www.nirsoft.net/utils/multi_monitor_tool.html>
- Freeware, by Nir Sofer

Be aware that enabling or disabling a display **renumbers deskmux's monitor
indices**, which is why the watcher resolves the LG by model string at startup
instead of trusting an index.
