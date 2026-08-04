@echo off
setlocal EnableDelayedExpansion
for %%I in ("%~dp0.") do set "PROJECT=%%~nxI"
title Push to GitHub - !PROJECT!
cd /d "%~dp0"

echo ====================================================
echo   Push !PROJECT! to GitHub
echo ====================================================
echo.

where git >nul 2>&1
if errorlevel 1 (
    echo ERROR: Git not installed.
    echo Download: https://git-scm.com/download/win
    pause
    exit /b 1
)

if not exist ".git" (
    echo ERROR: Git repo not linked yet.
    echo.
    echo FIRST TIME for this project:
    echo   1. Create empty repo on GitHub.com
    echo   2. Run: c:\projects\scripts\setup_github_repo.bat
    echo.
    echo Guide: c:\projects\scripts\GITHUB_ALL_PROJECTS_GUIDE.docx
    pause
    exit /b 1
)

set MSG=%~1
if "%MSG%"=="" (
    set /p MSG="Commit message - what did you change?: "
)
if "%MSG%"=="" set MSG=!PROJECT! update %date% %time%

echo.
echo Adding files...
git add .

echo.
echo Changed files:
git status --short
echo.

git commit -m "%MSG%"
if errorlevel 1 (
    echo No new changes to commit. Trying push only...
)

echo.
echo Uploading to GitHub...
git push
if errorlevel 1 (
    echo.
    echo PUSH FAILED.
    echo - Username: saleem26666
    echo - Password: Personal Access Token (same token as ISP - no new token needed)
    echo - Token: https://github.com/settings/tokens
    pause
    exit /b 1
)

echo.
echo ====================================================
echo   SUCCESS! !PROJECT! saved on GitHub.
for /f "delims=" %%u in ('git remote get-url origin 2^>nul') do echo   %%u
echo ====================================================
pause
