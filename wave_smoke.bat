@echo off
rem Open the smoke test waveform (build\out.vcd) in GTKWave
cd /d %~dp0

if not exist build\out.vcd (
    echo NO SMOKE WAVEFORM. Run sim.bat first.
    pause
    exit /b 1
)

echo Opening smoke waveform: build\out.vcd
where gtkwave >nul 2>nul
if %errorlevel%==0 (
    gtkwave build\out.vcd
) else if exist "C:\iverilog\gtkwave\bin\gtkwave.exe" (
    "C:\iverilog\gtkwave\bin\gtkwave.exe" build\out.vcd
) else (
    echo gtkwave.exe not found. Check your iverilog install.
    pause
    exit /b 1
)
