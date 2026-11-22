@echo off
REM ============================================================
REM  Fallen Doll + UE4SS (MotionBridge fd_tcode_probe) launcher
REM
REM  1) checks the loopback address the client talks to
REM  2) starts the local license server on 127.0.0.1:7900 if needed
REM  3) starts MotionBridge desktop if it can be found
REM  4) starts the game with the full argument set; UE4SS loads
REM     through dwmapi.dll, the mod needs no extra step
REM
REM  ASCII only on purpose: cmd.exe decodes .bat with the system
REM  code page, any non-ASCII byte here can be split into bogus
REM  commands. All real logic lives in the .py files.
REM ============================================================
chcp 65001 >nul 2>nul
setlocal EnableExtensions
cd /d "%~dp0"
set "HERE=%~dp0"
set "EXE=%HERE%Paralogue\Binaries\Win64\Paralogue-Win64-Shipping.exe"
set "U4=%HERE%Paralogue\Binaries\Win64\ue4ss"

echo.
echo   ============================================
echo    Fallen Doll  +  MotionBridge mod
echo   ============================================
echo.

if exist "%EXE%" goto havegame
echo   [!] Game exe not found:
echo       %EXE%
echo       Extract the whole archive first.
pause
exit /b 1

:havegame
if exist "%U4%\UE4SS.dll" goto havemod
echo   [!] Mod not installed (ue4ss\UE4SS.dll missing).
echo       Run "Install Mod.cmd" from the MotionBridge mod package first.
pause
exit /b 1

:havemod
tasklist /FI "IMAGENAME eq Paralogue-Win64-Shipping.exe" 2>nul | find /i "Paralogue-Win64" >nul
if errorlevel 1 goto noping
echo   [!] The game is already running. Close it first.
pause
exit /b 1

:noping
set "PYCMD="
where python >nul 2>nul && set "PYCMD=python"
if defined PYCMD goto havepython
where py >nul 2>nul && set "PYCMD=py"
if defined PYCMD goto havepython
echo   [!] Python not found. Run the one-click setup file once.
pause
exit /b 1

:havepython
REM ---------------- 1) loopback alias ----------------
powershell -NoProfile -Command "try{$s=New-Object Net.Sockets.Socket('InterNetwork','Stream','Tcp');$s.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Parse('62.106.75.243'),0)));$s.Close();exit 0}catch{exit 1}"
if not errorlevel 1 goto loopbackok
echo   [!] 62.106.75.243 is not bound to the loopback adapter.
echo       Right click the one-click setup .bat, "Run as administrator",
echo       then choose the "bind loopback address" menu item once.
pause
exit /b 1

:loopbackok
echo   [1/4] loopback address 62.106.75.243 : ok

REM ---------------- 2) local license server ----------------
powershell -NoProfile -Command "try{$c=New-Object Net.Sockets.TcpClient;$c.Connect('127.0.0.1',7900);$c.Close();exit 0}catch{exit 1}"
if not errorlevel 1 goto serverup
echo   [2/4] license server not running, starting it ...
powershell -NoProfile -Command "$g='%~dp0'; $env:FD_CHAL='proof'; $env:FD_KEY_ID='root-2026'; $py=Get-ChildItem -LiteralPath $g -Filter *.py | Where-Object { $_.Name -notin @('deploy.py','diagnose.py','checkpak.py') } | Select-Object -First 1; if(-not $py){ exit 2 }; Start-Process -FilePath '%PYCMD%' -ArgumentList $py.FullName -WorkingDirectory $g -WindowStyle Hidden"
if not errorlevel 1 goto serverwait
echo   [!] Could not find the license server script (*.py) in this folder.
pause
exit /b 1

:serverwait
for /l %%i in (1,1,40) do (
    powershell -NoProfile -Command "try{$c=New-Object Net.Sockets.TcpClient;$c.Connect('127.0.0.1',7900);$c.Close();exit 0}catch{exit 1}"
    if not errorlevel 1 goto serverup
    timeout /t 1 /nobreak >nul
)
echo   [!] License server did not answer on port 7900. Check logs\server.log
pause
exit /b 1

:serverup
echo   [2/4] license server 127.0.0.1:7900 : ok

REM ---------------- 3) MotionBridge desktop (optional) ----------------
set "MB="
if not defined MOTIONBRIDGE_EXE goto mblook
if not exist "%MOTIONBRIDGE_EXE%" goto mblook
set "MB=%MOTIONBRIDGE_EXE%"
goto mbstart

:mblook
for %%p in (
    "%LOCALAPPDATA%\Programs\MotionBridge\MotionBridge.exe"
    "%LOCALAPPDATA%\MotionBridge\MotionBridge.exe"
    "%APPDATA%\MotionBridge\MotionBridge.exe"
    "%ProgramFiles%\MotionBridge\MotionBridge.exe"
    "%USERPROFILE%\Desktop\MotionBridge.exe"
    "%USERPROFILE%\Downloads\MotionBridge.exe"
    "%HERE%MotionBridge\MotionBridge.exe"
) do (
    if exist "%%~p" set "MB=%%~p"
)
if defined MB goto mbstart
echo   [3/4] MotionBridge desktop : not found (mod still runs, but no stream / device output)
goto gamelaunch

:mbstart
echo   [3/4] MotionBridge desktop : %MB%
start "" "%MB%"
timeout /t 3 /nobreak >nul

REM ---------------- 4) game ----------------
:gamelaunch
echo   [4/4] starting game with UE4SS ...
set "FD_TCODE_FORCE_GATE=1"
start "" "%EXE%" -UserDir="%HERE%Paralogue" -NotInstalled -nosteam -DisablePlugins=CacheSignatureVerifier -TestSteamCode=REHOSTLOCAL -RehostUseSettings
powershell -NoProfile -Command "$t=0.0; while($t -lt 180){ if(Get-Process -Name 'Paralogue-Win64-Shipping' -ErrorAction SilentlyContinue | Where-Object {$_.MainWindowHandle -ne 0}){ break }; Start-Sleep -Milliseconds 400; $t+=0.4 }"
echo.
echo   Game window is up.
echo   Mod log   : Paralogue\Binaries\Win64\ue4ss\UE4SS.log
echo   Mod stream: %%USERPROFILE%%\.f8\studio\games\fallen-doll\runtime\fd-skeleton.ndjson
echo.
endlocal
exit /b 0
