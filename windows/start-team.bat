@echo off
rem ============================================================
rem  herdr-team Windows one-click launcher (for everyone)
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
rem --- Set HERDR_TEAM_SKIP_CHECK=1 to bypass this check ---
if "%HERDR_TEAM_SKIP_CHECK%"=="1" (
  echo [WARN] Skipping dependency check (HERDR_TEAM_SKIP_CHECK=1) / 의존성 점검 생략
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
    echo.
    echo To install automatically on Windows 10/11, run these in PowerShell as admin:
    echo Windows 10/11에서 자동 설치하려면 관리자 PowerShell에서 실행:
    echo   winget install --id Git.Git -e --source winget
    echo   wsl --install
    echo Then restart Windows and double-click start-team.bat again.
    echo 설치 후 Windows를 다시 시작하고 start-team.bat을 다시 더블클릭하세요.
    echo.
    echo To skip this check (advanced): set HERDR_TEAM_SKIP_CHECK=1
    echo 점검 생략(고급): HERDR_TEAM_SKIP_CHECK=1 설정
    pause
    exit /b 1
  )
)
)

rem --- Preset menu only when no args and no env (defaults to dev after 10s) ---
rem --- 프리셋 메뉴: 인자도 env도 없을 때만 (10초 무입력 시 dev) ---
set "PRESET_ARG="
if "%~1"=="" (
  if not defined HERDR_TEAM_PRESET (
    echo Select AI team preset / AI 팀 프리셋 선택:
    echo   1^) dev - Software Development (개발 4인 팀, 기본값)
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
    echo [dry-run] wsl bash "%WSL_REPO%/bin/herdr-team" --cwd "%WSL_REPO%" %PRESET_ARG% %*
  ) else (
    wsl bash "%WSL_REPO%/bin/herdr-team" --cwd "%WSL_REPO%" %PRESET_ARG% %*
    if errorlevel 1 (
      echo [FAILED] Team setup exited with an error / [실패] 팀 셋업이 오류로 종료되었습니다.
      pause
      exit /b 1
    )
  )
) else (
  set "MSYS_REPO=%REPO:\=/%"
  if "%HERDR_TEAM_DRYRUN%"=="1" (
    echo [dry-run] "%ProgramFiles%\Git\bin\bash.exe" "%MSYS_REPO%/bin/herdr-team" --cwd "%MSYS_REPO%" %PRESET_ARG% %*
  ) else (
    "%ProgramFiles%\Git\bin\bash.exe" "%MSYS_REPO%/bin/herdr-team" --cwd "%MSYS_REPO%" %PRESET_ARG% %*
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
