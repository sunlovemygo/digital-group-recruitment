@echo off
rem Open the random test waveform (build\random.vcd) in GTKWave
cd /d %~dp0

if not exist build\random.vcd (
    echo NO RANDOM WAVEFORM. Run sim_random.bat first.
    pause
    exit /b 1
)

echo Opening random waveform: build\random.vcd
where gtkwave >nul 2>nul
if %errorlevel%==0 (
    gtkwave build\random.vcd
) else if exist "C:\iverilog\gtkwave\bin\gtkwave.exe" (
    "C:\iverilog\gtkwave\bin\gtkwave.exe" build\random.vcd
) else (
    echo gtkwave.exe not found. Check your iverilog install.
    pause
    exit /b 1
)
