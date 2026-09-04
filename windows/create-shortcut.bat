@echo off
rem ============================================================
rem  Create desktop shortcut (English primary) / 바탕화면 바로가기 생성
rem  Run this to create a "Start AI Team" shortcut on the desktop.
rem  실행하면 바탕화면에 "Start AI Team" 바로가기가 생깁니다.
rem ============================================================
chcp 65001 >nul
setlocal

set "TARGET=%~dp0start-team.bat"
set "DESKTOP=%USERPROFILE%\Desktop"
if not exist "%DESKTOP%" set "DESKTOP=%USERPROFILE%\OneDrive\Desktop"
if not exist "%DESKTOP%" (
  echo [ERROR] Desktop folder not found / [오류] 바탕화면 폴더를 찾을 수 없습니다: "%USERPROFILE%"
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ws = New-Object -ComObject WScript.Shell; $sc = $ws.CreateShortcut('%DESKTOP%\Start AI Team.lnk'); $sc.TargetPath = '%TARGET%'; $sc.WorkingDirectory = '%~dp0'; $sc.Save()"
if errorlevel 1 (
  echo [FAILED] Shortcut creation failed / [실패] 바로가기 생성 실패
  pause
  exit /b 1
)

echo [OK] Desktop shortcut created / [완료] 바탕화면 바로가기 생성: "%DESKTOP%\Start AI Team.lnk"
if not "%HERDR_TEAM_NOPAUSE%"=="1" pause
endlocal
exit /b 0
