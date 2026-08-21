@echo off
title Budget Pro — Build APK
cd /d "%~dp0"
setlocal EnableDelayedExpansion

REM Git (Flutter needs it)
if exist "C:\Program Files\Git\cmd\git.exe" set "PATH=C:\Program Files\Git\cmd;%PATH%"
if exist "C:\Program Files (x86)\Git\cmd\git.exe" set "PATH=C:\Program Files (x86)\Git\cmd;%PATH%"

REM Flutter — PATH me na ho to common folders se dhoondo
where flutter >nul 2>&1
if errorlevel 1 (
  for %%D in (
    "C:\flutter\bin"
    "D:\flutter\bin"
    "%LOCALAPPDATA%\flutter\bin"
    "%USERPROFILE%\flutter\bin"
    "%USERPROFILE%\develop\flutter\bin"
    "%USERPROFILE%\development\flutter\bin"
    "C:\src\flutter\bin"
    "C:\dev\flutter\bin"
    "D:\src\flutter\bin"
    "D:\dev\flutter\bin"
  ) do (
    if exist "%%~D\flutter.bat" (
      set "PATH=%%~D;%PATH%"
      goto :flutter_found
    )
  )
  echo [ERROR] Flutter nahi mila.
  echo Flutter SDK install karein, ya yeh script me path set karein.
  echo Example: C:\flutter\bin
  echo https://docs.flutter.dev/get-started/install/windows
  pause
  exit /b 1
)
:flutter_found
where flutter >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Flutter PATH me add nahi ho saka.
  pause
  exit /b 1
)

echo.
echo === Flutter ===
call flutter --version
if errorlevel 1 (
  echo [ERROR] Flutter chal nahi saka.
  pause
  exit /b 1
)

echo.
echo === pub get ===
call flutter pub get
if errorlevel 1 (
  echo [ERROR] flutter pub get fail.
  pause
  exit /b 1
)

echo.
echo === Release APK build ===
if /i "%~1"=="split" (
  echo Split APKs: arm64 / arm32 / x86_64  ^(tez nahi, 3 phones types^)
  call flutter build apk --release --split-per-abi
) else if /i "%~1"=="fat" (
  echo Fat APK — 1 file, sab phones  ^(sab se slow^)
  call flutter build apk --release
) else if /i "%~1"=="clean" (
  echo Clean + arm64 APK
  call flutter clean
  call flutter pub get
  call flutter build apk --release --target-platform android-arm64
) else (
  echo Fast APK — sirf arm64  ^(aaj kal ke almost sab phones^)
  call flutter build apk --release --target-platform android-arm64
)

if errorlevel 1 (
  echo.
  echo [ERROR] APK build fail. Upar wala error check karein.
  pause
  exit /b 1
)

set "APK_DIR=%~dp0build\app\outputs\flutter-apk"
echo.
echo ========================================
echo  OK — APK ready
echo  Folder: %APK_DIR%
echo ========================================
echo.
if exist "%APK_DIR%\*.apk" (
  dir /b "%APK_DIR%\*.apk"
) else (
  echo [WARN] APK file nahi mili is folder me.
)
echo.
echo Phone pe install: app-release.apk
echo Named copy: BudgetPro_v^<version^>_^<date^>.apk
echo.
echo Extra options:
echo   build_apk.bat         = tez arm64 APK ^(default^)
echo   build_apk.bat split   = arm64 + arm32 + x86_64 alag files
echo   build_apk.bat fat     = 1 bari APK sab phones ke liye
echo   build_apk.bat clean   = flutter clean ke baad arm64 build
echo.

if exist "%APK_DIR%" explorer "%APK_DIR%"
pause
endlocal
