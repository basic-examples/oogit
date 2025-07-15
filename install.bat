@echo off

for %%I in (install.ps1) do powershell -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File \"\"%%~fI\"\"' -Verb RunAs"
