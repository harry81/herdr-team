@echo off
rem ============================================================
rem  herdr-watcher Windows one-click launcher (for everyone)
rem  Windows 원클릭 런처 (Watcher 실행용)
rem  Usage / 사용법: double-click (더블클릭), or start-watcher.bat [--prefix PREFIX]
rem  Env vars / 환경변수: HERDR_TEAM_REPO (repo path override),
rem             HERDR_TEAM_NOPAUSE=1 (skip final pause)
rem ============================================================
chcp 65001 >nul
setlocal EnableDelayedExpansion

rem --- 저장소 루트 해결 ---
if defined HERDR_TEAM_REPO (
  set "REPO=%HERDR_TEAM_REPO%"
) else (
  for %%I in ("%~dp0..") do set "REPO=%%~fI"
)

rem --- Backend: WSL first, Git-Bash fallback ---
if "%HERDR_TEAM_SKIP_CHECK%"=="1" (
  set "BACKEND=wsl"
) else (
  where wsl >nul 2>nul
  if not errorlevel 1 (
    set "BACKEND=wsl"
  ) else (
    if exist "%ProgramFiles%\Git\bin\bash.exe" (
      set "BACKEND=gitbash"
    ) else (
      echo [ERROR] Neither WSL nor Git-Bash was found.
      echo [오류] WSL 또는 Git-Bash를 찾을 수 없습니다.
      pause
      exit /b 1
    )
  )
)

rem --- herdr precheck (herdr-team runs on top of herdr) / herdr 사전 점검 ---
rem --- Fail fast when herdr is missing; set HERDR_TEAM_SKIP_CHECK=1 to bypass ---
if "%HERDR_TEAM_SKIP_CHECK%"=="1" (
  echo [WARN] Skipping herdr precheck (HERDR_TEAM_SKIP_CHECK=1) / herdr 사전 점검 생략
) else (
  if "%BACKEND%"=="wsl" (
    for /f "delims=" %%p in ('wsl wslpath -u "%REPO%"') do set "WSL_REPO=%%p"
    wsl bash "%WSL_REPO%/bin/herdr-team" --precheck
  ) else (
    set "MSYS_REPO=%REPO:\=/%"
    "%ProgramFiles%\Git\bin\bash.exe" "%MSYS_REPO%/bin/herdr-team" --precheck
  )
  if errorlevel 1 (
    echo [ERROR] herdr CLI not found - herdr-team runs on top of herdr.
    echo [오류] herdr CLI 를 찾을 수 없습니다. herdr-team는 herdr 위에서 동작합니다.
    echo   Install / 설치: curl -fsSL https://herdr.dev/install.sh ^| sh
    echo   Windows: powershell -ExecutionPolicy Bypass -c "irm https://herdr.dev/install.ps1 ^| iex"
    echo   Verify / 확인: herdr --version
    echo   Bypass / 우회: set HERDR_TEAM_SKIP_CHECK=1
    pause
    exit /b 127
  )
)

echo ========================================================
echo  Herdr Team Watcher (htw) Windows Launcher
echo  에이전트 멈춤 감시 및 셸 승인 팝업 자동 처리기
echo ========================================================
echo.

rem --- 실행 ---
if "%BACKEND%"=="wsl" (
  for /f "delims=" %%p in ('wsl wslpath -u "%REPO%"') do set "WSL_REPO=%%p"
  if not defined WSL_REPO (
    echo [ERROR] WSL path conversion failed: "%REPO%"
    pause
    exit /b 1
  )
  wsl python3 "%WSL_REPO%/bin/herdr-watcher" %*
  if errorlevel 1 (
    echo [FAILED] Watcher exited with an error.
    pause
    exit /b 1
  )
) else (
  set "MSYS_REPO=%REPO:\=/%"
  "%ProgramFiles%\Git\bin\bash.exe" -c "python3 '%MSYS_REPO%/bin/herdr-watcher' $* || python '%MSYS_REPO%/bin/herdr-watcher' $*" -- %*
  if errorlevel 1 (
    echo [FAILED] Watcher exited with an error.
    pause
    exit /b 1
  )
)

if not "%HERDR_TEAM_NOPAUSE%"=="1" pause
endlocal
exit /b 0
