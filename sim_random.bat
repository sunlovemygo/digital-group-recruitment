@echo off
rem One-click: regenerate random tb -> compile -> simulate (native Windows, iverilog v12)
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

echo === step 1/3: generate random tb (golden_model v2) ===
python model\gen_random_tb.py 100
if errorlevel 1 (
    echo GEN FAILED
    pause
    exit /b 1
)

echo === step 2/3: compile ===
"%IV%" -g2005 -Wall -o build\tb_random.vvp tb\tb_attention_random.v rtl\attention_ip.v
if errorlevel 1 (
    echo COMPILE FAILED
    pause
    exit /b 1
)

echo === step 3/3: simulate ===
"%VP%" -n build\tb_random.vvp
if errorlevel 1 (
    echo SIMULATION FAILED
    pause
    exit /b 1
)
echo.
echo === SIMULATION DONE ===
pause
