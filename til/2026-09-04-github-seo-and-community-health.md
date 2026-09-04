# TIL: 오픈소스 GitHub SEO와 커뮤니티 헬스 설계 (2026-09-04)

`herdr-team` 공개 저장소의 검색 노출·신뢰 신호·기여자 유입 장치를 만들며 정리한 이론.

## 1. GitHub SEO 랭킹 요소 (검색: site 내 + 구글)

- **H1 + 첫 문단 키워드**: 저장소명은 `herdr-team`, 첫 줄에
  "4-pane AI crew / terminal / plan·build·gate-check"를 배치한다.
  GitHub 검색은 README H1·About description·topics 순으로 가중치를 둔다.
- **About description ≤160자**: 139자로 고정. 앞 60자에 핵심 키워드
  (AI crew, terminal, plan/build/verify)를 몰아넣고 뒤에 페르소나
  (solo apps, small biz, TDD)를 붙인다. 잘리면 앞부분만 노출되므로
  중요도 내림차순이 원칙이다.
- **배지는 신뢰 신호이자 키워드**: Shields.io 4종(License/Platform/PRs/Stars)을
  H1 바로 아래에 둔다. 사람은 "유지되는 프로젝트"로 읽고, 크롤러는 링크 그래프를
  읽는다. Stars 배지는 `github/stars/...?style=social` 한 줄로 자가 증식 고리를 만든다.
- **설치 원라이너는 실URL로**: `<this-repo>` 플레이스홀더는 복사-붙여넣기
  실패 = 이탈이다. `raw.githubusercontent.com/.../main/install.sh` 실URL을 박고,
  테스트 가드레일로 URL 문자열 존재를 단언해 플레이스홀더 회귀를 막는다.

## 2. Topics 14개 전략

- GitHub topics 상한(20개) 안에서 **발견 경로 3종을 커버**한다:
  (a) 기술 스택(`bash`, `shell`, `cli`, `terminal`, `windows`, `wsl`),
  (b) 도메인(`ai-agents`, `multi-agent`, `orchestration`, `automation`, `tdd`),
  (c) 사용자(`developer-tools`, `side-project`, `small-business`).
- 14개로 둔 이유: 핵심만 남기고 여백(6)을 두면 출시 후 검색어 반응을 보고
  추가할 수 있다. 처음부터 20개를 채우면 최적화 여지가 없다.
- 적용은 `gh repo edit --add-topic` add-only라 재실행 멱등.
  `scripts/repo-meta.sh`로 원클릭화하고, `gh` 미설치 시 실행 예정 명령을
  dry-run 출력으로 보여줘 복사 실행 가능하게 한다.

## 3. 커뮤니티 헬스 파일 설계

- 최소 세트: `ci.yml`(3개 테스트 스위트, ubuntu-latest) +
  `bug_report.yml`/`feature_request.yml`(YAML 폼, labels 자동) +
  `PR_TEMPLATE`(검증 로그 붙여넣기 강제) + `CONTRIBUTING.md` + `SECURITY.md`.
- 이슈 폼은 **재현 가능성**에 최적화한다: bug에는 명령·기대·실제·로그 4칸,
  feature에는 문제·제안·범위(preset/CLI/런처/릴리스/문서) 드롭다운.
  maintainer의 첫 응답 시간을 줄이는 것이 목적이다.
- PR 템플릿에 테스트 결과 붙여넣기 칸 + `.bat` CRLF 체크를 넣으면
  리뷰 전 결함이 절반으로 준다 (이번 작업의 CRLF 회귀가 근거).
- `SECURITY.md`는 통로(비공개 제보 메일 경로)와 범위 특기
  (install 파이프 사전 검토, .bat 무자동설치 원칙)를 명시한다.
  보안 정책도 UX다 — 제보자가 다음 행동을 알면 된다.
