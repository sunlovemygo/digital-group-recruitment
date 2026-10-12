@echo off
rem Open the latest VCD waveform in GTKWave (works with iverilog v12 default install layout)
cd /d %~dp0

set "LATEST="
for /f "delims=" %%f in ('dir /b /o-d build\*.vcd 2^>nul') do (
    set "LATEST=%%f"
    goto :found
)
:found

if "%LATEST%"=="" (
    echo NO WAVEFORM. Run sim.bat or sim_random.bat first.
    pause
    exit /b 1
)

echo Opening latest waveform: build\%LATEST%
where gtkwave >nul 2>nul
if %errorlevel%==0 (
    gtkwave "build\%LATEST%"
) else if exist "C:\iverilog\gtkwave\bin\gtkwave.exe" (
    "C:\iverilog\gtkwave\bin\gtkwave.exe" "build\%LATEST%"
) else (
    echo gtkwave.exe not found. Check your iverilog install.
    pause
    exit /b 1
)
