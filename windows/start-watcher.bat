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
  rem --- WSL is only usable if a distro can actually run bash; the wsl.exe stub exists even when WSL is not installed ---
  set "BACKEND="
  for /f "delims=" %%p in ('wsl bash -lc "echo wsl-ok" 2^>nul') do if /i "%%p"=="wsl-ok" set "BACKEND=wsl"
  if not defined BACKEND if exist "%ProgramFiles%\Git\bin\bash.exe" set "BACKEND=gitbash"
  if not defined BACKEND (
    echo [ERROR] Neither WSL nor Git-Bash was found.
    echo [오류] WSL 또는 Git-Bash를 찾을 수 없습니다.
    pause
    exit /b 1
  )
)

rem --- herdr precheck (herdr-team runs on top of herdr) / herdr 사전 점검 ---
rem --- Fail fast when herdr is missing; set HERDR_TEAM_SKIP_CHECK=1 to bypass ---
if "%HERDR_TEAM_SKIP_CHECK%"=="1" (
  echo [WARN] Skipping herdr precheck ^(HERDR_TEAM_SKIP_CHECK=1^) / herdr 사전 점검 생략
) else (
  if "%BACKEND%"=="wsl" (
    for /f "delims=" %%p in ('wsl wslpath -u "%REPO%"') do set "WSL_REPO=%%p"
    wsl bash "!WSL_REPO!/bin/herdr-team" --precheck
  ) else (
    set "MSYS_REPO=%REPO:\=/%"
    "%ProgramFiles%\Git\bin\bash.exe" "!MSYS_REPO!/bin/herdr-team" --precheck
  )
  if errorlevel 127 (
    echo [ERROR] herdr CLI not found - herdr-team runs on top of herdr.
    echo [오류] herdr CLI 를 찾을 수 없습니다. herdr-team는 herdr 위에서 동작합니다.
    echo   Install / 설치: curl -fsSL https://herdr.dev/install.sh ^| sh
    echo   Windows: powershell -ExecutionPolicy Bypass -c "irm https://herdr.dev/install.ps1 ^| iex"
    echo   Verify / 확인: herdr --version
    echo   Bypass / 우회: set HERDR_TEAM_SKIP_CHECK=1
    pause
    exit /b 127
  )
  if errorlevel 126 (
    echo [ERROR] jq not found - herdr-team uses jq to parse herdr JSON.
    echo [오류] jq 를 찾을 수 없습니다. herdr-team는 herdr JSON 파싱에 jq를 사용합니다.
    echo   Install / 설치: winget install --id jqlang.jq -e
    echo   Verify / 확인: jq --version
    echo   Bypass / 우회: set HERDR_TEAM_SKIP_CHECK=1
    pause
    exit /b 126
  )
  if errorlevel 1 (
    echo [ERROR] dependency check failed / 의존성 점검 실패
    pause
    exit /b 1
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
  if not "!WSL_REPO!"=="" (
    wsl python3 "!WSL_REPO!/bin/herdr-watcher" %*
    if errorlevel 1 (
      echo [FAILED] Watcher exited with an error.
      pause
      exit /b 1
    )
  ) else (
    echo [ERROR] WSL path conversion failed: "%REPO%"
    pause
    exit /b 1
  )
) else (
  set "MSYS_REPO=%REPO:\=/%"
  "%ProgramFiles%\Git\bin\bash.exe" -c "python3 '!MSYS_REPO!/bin/herdr-watcher' $* || python '!MSYS_REPO!/bin/herdr-watcher' $*" -- %*
  if errorlevel 1 (
    echo [FAILED] Watcher exited with an error.
    pause
    exit /b 1
  )
)

if not "%HERDR_TEAM_NOPAUSE%"=="1" pause
endlocal
exit /b 0
