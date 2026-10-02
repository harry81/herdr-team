@echo off
rem ============================================================
rem  herdr-team Windows one-click installer (for everyone)
rem  Windows 원클릭 설치기
rem  Installs hts/htw/ht/herdr-team/herdr-team-setup .cmd shims into
rem  %HERDR_TEAM_BIN_DIR% (default: %USERPROFILE%\bin) and registers User PATH.
rem  Prereq / 전제: herdr CLI (https://herdr.dev).
rem  Env / 환경변수:
rem    HERDR_TEAM_REPO         repo path override / 저장소 경로 재지정
rem    HERDR_TEAM_BIN_DIR      install dir / 설치 경로 (default %USERPROFILE%\bin)
rem    HERDR_TEAM_SKIP_CHECK=1 bypass backend/herdr checks / 점검 우회
rem    HERDR_TEAM_DRYRUN=1     print plan only, no writes / 계획만 출력
rem    HERDR_TEAM_NOPAUSE=1    skip final pause / 끝에 pause 생략
rem ============================================================
chcp 65001 >nul
setlocal EnableDelayedExpansion

rem --- 저장소 루트 해결 (이 파일의 부모 디렉토리) ---
if defined HERDR_TEAM_REPO (
  set "REPO=%HERDR_TEAM_REPO%"
) else (
  for %%I in ("%~dp0..") do set "REPO=%%~fI"
)

rem --- 인자 처리: --help 외 알 수 없는 인자는 오류(exit /b 2) ---
if not "%~1"=="" (
  if /i "%~1"=="--help" goto :usage
  if /i "%~1"=="-h" goto :usage
  if /i "%~1"=="/?" goto :usage
  echo [ERROR] Unknown argument / 알 수 없는 인자: %*
  exit /b 2
)

set "BIN_DIR=%HERDR_TEAM_BIN_DIR%"
if not defined BIN_DIR set "BIN_DIR=%USERPROFILE%\bin"

rem --- Backend: WSL first, Git-Bash fallback / 백엔드 선택: WSL 우선, 없으면 Git-Bash ---
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
      echo Then restart Windows and run install.bat again.
      echo 설치 후 Windows를 다시 시작하고 install.bat을 다시 실행하세요.
      echo.
      echo To skip this check (advanced): set HERDR_TEAM_SKIP_CHECK=1
      echo 점검 생략(고급): HERDR_TEAM_SKIP_CHECK=1 설정
      if not "%HERDR_TEAM_NOPAUSE%"=="1" pause
      exit /b 1
    )
  )
)

rem --- herdr precheck via backend / herdr 사전 점검 ---
if "%HERDR_TEAM_SKIP_CHECK%"=="1" (
  echo [WARN] Skipping herdr precheck (HERDR_TEAM_SKIP_CHECK=1) / herdr 사전 점검 생략
) else (
  if "%BACKEND%"=="wsl" (
    for /f "delims=" %%p in ('wsl wslpath -u "%REPO%"') do set "WSL_REPO=%%p"
    if not defined WSL_REPO (
      echo [ERROR] WSL path conversion failed / WSL 경로 변환 실패: "%REPO%"
      if not "%HERDR_TEAM_NOPAUSE%"=="1" pause
      exit /b 1
    )
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
    if not "%HERDR_TEAM_NOPAUSE%"=="1" pause
    exit /b 127
  )
)

rem --- DRYRUN: 계획만 출력하고 쓰기 0 ---
if "%HERDR_TEAM_DRYRUN%"=="1" (
  echo [dry-run] install dir / 설치 경로: "%BIN_DIR%"
  echo [dry-run] create / 생성: hts.cmd htw.cmd ht.cmd herdr-team.cmd herdr-team-setup.cmd
  echo [dry-run] each cmd: call "%REPO%\windows\start-team.bat" %%* ^(htw: start-watcher.bat^)
  echo [dry-run] PATH: [Environment]::SetEnvironmentVariable("Path", ..., "User") if missing
  if not "%HERDR_TEAM_NOPAUSE%"=="1" pause
  exit /b 0
)

rem --- 설치 (멱등: 내용 동일 시 스킵). 개별 실패는 누적하고 나머지는 계속 진행 ---
if not exist "%BIN_DIR%" mkdir "%BIN_DIR%"
set "RC=0"

call :install_cmd "%BIN_DIR%\hts.cmd" "start-team.bat"
if errorlevel 1 set "RC=1"
call :install_cmd "%BIN_DIR%\ht.cmd" "start-team.bat"
if errorlevel 1 set "RC=1"
call :install_cmd "%BIN_DIR%\herdr-team.cmd" "start-team.bat"
if errorlevel 1 set "RC=1"
call :install_cmd "%BIN_DIR%\herdr-team-setup.cmd" "start-team.bat"
if errorlevel 1 set "RC=1"
call :install_cmd "%BIN_DIR%\htw.cmd" "start-watcher.bat"
if errorlevel 1 set "RC=1"

rem --- PATH 등록: 미존재 시에만, PowerShell User 범위 (setx 금지) ---
rem --- null/빈 User PATH(신규 계정)도 IsNullOrEmpty 분기로 안전 처리 ---
powershell -NoProfile -ExecutionPolicy Bypass -Command "$d=[Environment]::GetEnvironmentVariable('Path','User'); if ([string]::IsNullOrEmpty($d)) { [Environment]::SetEnvironmentVariable('Path','%BIN_DIR%','User') } elseif ($d -notlike '*%BIN_DIR%*') { [Environment]::SetEnvironmentVariable('Path', ($d.TrimEnd(';') + ';%BIN_DIR%'), 'User') }"
if errorlevel 1 (
  echo [WARN] Could not update User PATH automatically / User PATH 자동 등록 실패
  echo [WARN] Add manually / 수동 추가: %BIN_DIR%
)

if "%RC%"=="0" (
  echo [install] 완료. 새 터미널에서 `hts` 또는 `htw` 실행. / Done. Open a new terminal and run hts or htw.
) else (
  echo [ERROR] One or more wrappers failed to install / 일부 래퍼 설치 실패 (사용 가능: hts, htw, ht, herdr-team, herdr-team-setup)
  echo [ERROR] Failed wrappers are logged above as "[ERROR] Failed to write: <path>" / 실패 래퍼는 위 로그 참조
)
if not "%HERDR_TEAM_NOPAUSE%"=="1" pause
rem --- endlocal 이후 %RC% 소실 방지를 위해 한 줄에서 함께 처리 ---
endlocal & exit /b %RC%

:install_cmd
rem %1=dest cmd path, %2=launcher bat filename
set "DEST=%~1"
set "TMPF=%TEMP%\herdr_team_cmd_%RANDOM%%RANDOM%.tmp"
> "%TMPF%" echo @echo off
>>"%TMPF%" echo call "%REPO%\windows\%~2" %%*
if exist "%DEST%" (
  fc /b "%TMPF%" "%DEST%" >nul 2>&1
  if not errorlevel 1 (
    echo [skip] unchanged / 변경 없음: %DEST%
    del "%TMPF%" >nul 2>&1
    exit /b 0
  )
)
move /y "%TMPF%" "%DEST%" >nul
if errorlevel 1 (
  echo [ERROR] Failed to write / 쓰기 실패: %DEST%
  del "%TMPF%" >nul 2>&1
  exit /b 1
)
echo [installed] %DEST%
exit /b 0

:usage
echo Usage: install.bat
echo   Installs hts.cmd / htw.cmd / ht.cmd / herdr-team.cmd / herdr-team-setup.cmd
echo   into %%HERDR_TEAM_BIN_DIR%% (default %%USERPROFILE%%\bin) and registers User PATH.
echo   Prereq / 전제: herdr CLI ^(https://herdr.dev^).
echo   Env: HERDR_TEAM_REPO, HERDR_TEAM_BIN_DIR, HERDR_TEAM_SKIP_CHECK=1,
echo        HERDR_TEAM_DRYRUN=1, HERDR_TEAM_NOPAUSE=1
exit /b 0
