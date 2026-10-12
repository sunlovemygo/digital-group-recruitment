@echo off
rem One-click compile + simulate on native Windows (iverilog v12)
rem Works with or without C:\iverilog in PATH.
chcp 65001 >nul
cd /d %~dp0
if not exist build mkdir build

set "IV=iverilog.exe"
set "VP=vvp.exe"
where iverilog >nul 2>nul
if errorlevel 1 (
    if exist "C:\iverilog\bin\iverilog.exe" (
        set "IV=C:\iverilog\bin\iverilog.exe"
        set "VP=C:\iverilog\bin\vvp.exe"
    ) else (
        echo ERROR: iverilog.exe not found in PATH or C:\iverilog\bin
        exit /b 1
    )
)

"%IV%" -g2005 -Wall -o build\tb_attention_smoke.vvp tb\tb_attention_smoke.v rtl\attention_ip.v
if errorlevel 1 (
    echo COMPILE FAILED
    pause
    exit /b 1
)

"%VP%" -n build\tb_attention_smoke.vvp
if errorlevel 1 (
    echo SIMULATION FAILED
    pause
    exit /b 1
)
echo.
echo === SIMULATION DONE ===
pause
