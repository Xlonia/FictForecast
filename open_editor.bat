@echo off
rem FictForecast settings editor launcher (batch)
rem CLI alternative: godot --path <project> -- --open-editor
if defined GODOT_EXE (set "GODOT=%GODOT_EXE%") else (set "GODOT=D:\godot\Godot_v4.3-stable_mono_win64\Godot_v4.7.2-stable_win64.exe")
start "" "%GODOT%" --path "%~dp0" res://scenes/editor.tscn
