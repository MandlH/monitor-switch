' Starts the watcher with no console window.
'
' Placed in the Startup folder (shell:startup) so it runs at logon as the
' current user. Task Scheduler would also work but needs elevation to register,
' which the Startup folder does not.
'
' Adjust the path if the repository lives somewhere else.

Dim shell, script
Set shell = CreateObject("Wscript.Shell")
script = "D:\Monitor\monitor-switch\scripts\watch-usb-switch.ps1"

shell.Run "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & script & """", 0, False
