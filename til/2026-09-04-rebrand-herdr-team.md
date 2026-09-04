# TIL: 프로젝트 리브랜딩과 하위 호환 설계 (2026-09-04)

`herdr-team-setup` → `herdr-team` 리브랜딩(Option B: 정본 이전 + 레거시 래퍼)에서
정리한 패턴.

## 1. 정본 이전 + 얇은 래퍼 (Option B)

- `git mv bin/herdr-team-setup bin/herdr-team`으로 히스토리를 보존한 채 정본을
  이전하고, 구 이름은 인자 전달만 하는 3줄 래퍼 실파일로 남긴다:
  `exec "$SELF_DIR/herdr-team" "$@"`.
- 형제 경로 해결(`dirname "${BASH_SOURCE[0]}"`)은 직접 실행과 `~/bin` 심볼릭
  링크 경유 모두에서 동작한다. 양쪽에 정본·래퍼 링크를 같이 설치해야
  어느 호출 경로에서도 깨지지 않는다.
- 래퍼는 로직을 절대 복제하지 않는다(single source of truth). 동일 입력에 대한
  출력 바이트 동등성을 테스트로 단언하면(`diff` 비교) drift를 원천 차단한다.

## 2. 설치 링크의 안전한 세대교체

- `install.sh`의 `link()`는 이미 멱등 교체(`ln -sfn` + 실파일 백업)라서,
  4개 링크(`herdr-team`, `ht`, `hts`, `herdr-team-setup`)를 모두 정본으로
  가리키게 바꾸는 것만으로 기존 사용자의 구 심볼릭 링크가 자동 치유된다.
- 셸 마커는 문자열이 바뀌면(`herdr-team-setup:` → `herdr-team:`) 단순 append가
  중복 등록을 만든다. 구 마커 라인을 `sed` 제자리 교체로 마이그레이션한 뒤
  통상 경로로 진행하면 "정확히 1회" 불변량이 유지된다.
- 검증은 구 마커를 미리 심은 fixture에 설치를 돌려 신 마커 1회·구 마커 0회를
  단언하는 형태가 된다.

## 3. 문서·산출물명의 일괄 전환과 예외 관리

- 단순 문자열 치환(`herdr-team-setup` → `herdr-team`)은 빠르지만 예외가 있다:
  실제 디렉터리명, `~/templates/agent-team` 경로, `HERDR_TEAM_*` 환경변수는
  치환 대상이 아니다. 치환 후 `grep`으로 잔존 위치를 전수 확인하고,
  의도적 잔류(레거시 호환 안내 문구)만 남긴다.
- 사용자에게 보이는 이름(제목, usage, zip 기본 산출물명, LICENSE 저작권자)은
  전부 신명으로 통일하고, 구명은 "deprecated, fully compatible" 한 줄로 명시해
  검색·북마크·근육 기억(muscle memory)을 끊지 않는다.
- CRLF 파일(`.bat`)은 편집 후 개행 정규화를 반드시 다시 돌린다.
  에디터 기반 수정이 LF를 섞어 넣기 때문이다.
