# TIL: Linux, macOS, Windows 3대 OS 완전 지원 아키텍처 (2026-09-14)

## 1. Windows 원클릭 런처 아키텍처 (WSL & Git-Bash 하이브리드 브릿지)

Windows 환경에서 Linux/Unix 기반 도구(`bash`, `python3`, `herdr`)를 일반 사용자가 터미널 조작 없이 실행할 수 있도록 배치(`*.bat`) 런처를 설계할 때의 핵심 원칙:

1. **백엔드 탐색 및 자동 위임**:
   * `where wsl`로 1차 탐색, 부재 시 `%ProgramFiles%\Git\bin\bash.exe`로 폴백.
   * 둘 다 없을 경우 `winget install --id Git.Git`, `wsl --install`을 친절히 안내하고 종료.
2. **경로 변환 (Path Translation)**:
   * WSL: `wslpath -u "%REPO%"`를 통해 `/mnt/c/...` 형식으로 변환.
   * Git-Bash: `%REPO:\=/%` 치환을 통해 MSYS POSIX 경로 형식으로 변환.
3. **코드페이지 및 개행 문자 (Encoding & CRLF)**:
   * `chcp 65001 >nul`을 통해 한글 및 UTF-8 출력을 cmd.exe에서 깨짐 없이 렌더링.
   * Git 저장소 내 배치 파일은 반드시 CRLF(`\r\n`)를 유지해야 cmd.exe 파서 오류를 방지할 수 있음.
4. **Watcher 런처 신설 (`start-watcher.bat`)**:
   * 팀 런처(`start-team.bat`)에 이어 워처 런처를 제공함으로써 Windows 사용자도 더블클릭 한 번으로 백그라운드 워치독 데몬을 구동 가능.

---

## 2. macOS (BSD sed) vs Linux (GNU sed) 호환성 보장 패턴

* **문제점**:
  * Linux GNU sed: `sed -i "s/.../.../" file` (성공)
  * macOS BSD sed: `sed -i "s/.../.../" file` (오류: `sed: -i requires an argument`)  
    macOS는 `sed -i '' "s/.../.../" file`을 요구하지만, 이 구문은 GNU sed에서 빈 문자열 파일을 생성하려 시도함.
* **해결책 (원자적 임시 파일 교체 패턴)**:
  ```bash
  sed "s|^${LEGACY_MARKER}$|${MARKER}|" "$rc" > "$rc.tmp" && mv "$rc.tmp" "$rc"
  ```
  * `-i` 플래그 자체를 배제하고, 표준 출력 리다이렉션 후 `mv`로 덮어쓰는 방식을 취하면 Linux, macOS, FreeBSD 등 모든 POSIX 시스템에서 100% 동일하게 동작함.

---

## 3. 크로스 플랫폼 배포 zip 패키징 검증

* `scripts/build-zip.sh`에서 Linux/macOS 실행 파일(`bin/herdr-team`, `bin/herdr-watcher`)과 Windows 배치 파일(`windows/*.bat`, `start-*.bat`)이 모두 누락 없이 아카이브에 포함되도록 TDD 리그레션 테스트(`tests/test_install.sh`, `tests/test_windows_launcher.sh`)를 구축하여 배포 안정성을 유지함.
