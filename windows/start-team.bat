@echo off
rem ============================================================
rem  herdr-team-setup Windows one-click launcher (for everyone)
rem  Windows 원클릭 런처 (일반 사용자용)
rem  Usage / 사용법: double-click (더블클릭), or start-team.bat [prefix] [--preset dev|app|biz] [options]
rem  Env vars / 환경변수: HERDR_TEAM_REPO (repo path override / 저장소 경로 재지정),
rem             HERDR_TEAM_PRESET (dev|app|biz, skip menu / 메뉴 생략),
rem             HERDR_TEAM_DRYRUN=1 (simulate: print command only / 실행 명령만 출력),
rem             HERDR_TEAM_NOPAUSE=1 (skip final pause / 끝에 pause 생략)
rem ============================================================
chcp 65001 >nul
setlocal EnableDelayedExpansion

rem --- 저장소 루트 해결 (이 파일의 부모 디렉토리) ---
if defined HERDR_TEAM_REPO (
  set "REPO=%HERDR_TEAM_REPO%"
) else (
  for %%I in ("%~dp0..") do set "REPO=%%~fI"
}

rem --- Backend: WSL first, Git-Bash fallback / 백엔드 선택: WSL 우선, 없으면 Git-Bash ---
where wsl >nul 2>nul
if not errorlevel 1 (
  set "BACKEND=wsl"
) else (
  if exist "%ProgramFiles%\Git\bin\bash.exe" (
    set "BACKEND=gitbash"
  ) else (
    echo [ERROR] Neither WSL nor Git-Bash was found.
    echo [오류] WSL 또는 Git-Bash를 찾을 수 없습니다.
    echo        Please install WSL from the Microsoft Store or install Git for Windows.
    echo        Microsoft Store에서 WSL을 설치하거나 Git for Windows를 설치하세요.
    pause
    exit /b 1
  )
)

rem --- Preset menu only when no args and no env (defaults to dev after 10s) ---
rem --- 프리셋 메뉴: 인자도 env도 없을 때만 (10초 무입력 시 dev) ---
set "PRESET_ARG="
if "%~1"=="" (
  if not defined HERDR_TEAM_PRESET (
    echo Select AI team preset / AI 팀 프리셋 선택:
    echo   1^) dev - Software Development (개발 3인 팀, 기본값)
    echo   2^) app - Solo App ^& Idea Discovery (1인 앱/아이템)
    echo   3^) biz - Small Business Operations (스몰 비즈니스)
    choice /c 123 /t 10 /d 1 /n /m "Select [1-3] (default 1 after 10s / 10초 후 기본값 1): "
    if errorlevel 3 set "PRESET_ARG=--preset biz"
    if errorlevel 2 set "PRESET_ARG=--preset app"
    if "%PRESET_ARG%"=="" set "PRESET_ARG=--preset dev"
  ) else (
    set "PRESET_ARG=--preset %HERDR_TEAM_PRESET%"
  )
)

rem --- 실행 ---
if "%BACKEND%"=="wsl" (
  for /f "delims=" %%p in ('wsl wslpath -u "%REPO%"') do set "WSL_REPO=%%p"
  if not defined WSL_REPO (
    echo [ERROR] WSL path conversion failed / [오류] WSL 경로 변환 실패: "%REPO%"
    pause
    exit /b 1
  )
  if "%HERDR_TEAM_DRYRUN%"=="1" (
    echo [dry-run] wsl bash "%WSL_REPO%/bin/herdr-team-setup" --cwd "%WSL_REPO%" %PRESET_ARG% %*
  ) else (
    wsl bash "%WSL_REPO%/bin/herdr-team-setup" --cwd "%WSL_REPO%" %PRESET_ARG% %*
    if errorlevel 1 (
      echo [FAILED] Team setup exited with an error / [실패] 팀 셋업이 오류로 종료되었습니다.
      pause
      exit /b 1
    )
  )
) else (
  set "MSYS_REPO=%REPO:\=/%"
  if "%HERDR_TEAM_DRYRUN%"=="1" (
    echo [dry-run] "%ProgramFiles%\Git\bin\bash.exe" "%MSYS_REPO%/bin/herdr-team-setup" --cwd "%MSYS_REPO%" %PRESET_ARG% %*
  ) else (
    "%ProgramFiles%\Git\bin\bash.exe" "%MSYS_REPO%/bin/herdr-team-setup" --cwd "%MSYS_REPO%" %PRESET_ARG% %*
    if errorlevel 1 (
      echo [FAILED] Team setup exited with an error / [실패] 팀 셋업이 오류로 종료되었습니다.
      pause
      exit /b 1
    )
  )
)

if not "%HERDR_TEAM_NOPAUSE%"=="1" pause
endlocal
exit /b 0
