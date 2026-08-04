@echo off
title Budget Pro — Push to GitHub
cd /d "%~dp0"

where git >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Git nahi mila. Install: https://git-scm.com
  pause
  exit /b 1
)

if not exist ".git" (
  echo Git repo create kar raha hoon...
  git init -b main
  git remote add origin https://github.com/saleem26666/budget-pro.git
)

echo.
echo === Status ===
git status -sb
echo.

echo Files add / commit...
git add -A
git status -sb

git diff --cached --quiet
if errorlevel 1 (
  git commit -m "Update Budget Pro v2.1.1"
) else (
  echo Koi naya change commit ke liye nahi.
)

echo.
echo GitHub pe push...
git push -u origin main
if errorlevel 1 (
  echo.
  echo Normal push fail — final folder force push kar raha hoon...
  git push -u origin main --force
  if errorlevel 1 (
    echo.
    echo [ERROR] Push fail. GitHub login / internet check karein.
    pause
    exit /b 1
  )
)

echo.
echo OK — GitHub updated:
echo https://github.com/saleem26666/budget-pro
echo.
pause
