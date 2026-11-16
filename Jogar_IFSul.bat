@echo off
setlocal
set "GODOT_EXE=D:\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe"
if exist "%GODOT_EXE%" (
    start "" "%GODOT_EXE%" --path "%~dp0."
) else (
    start "" godot --path "%~dp0."
)
