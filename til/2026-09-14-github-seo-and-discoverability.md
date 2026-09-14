# TIL: GitHub 저장소 발견 가능성(SEO)과 메타데이터 최적화 (2026-09-14)

`herdr-team`의 description/topics/README 상단을 정비하며 재확인한 GitHub 검색·발견 원리.
(D4·D9·D10 = GitHub 공식 문서/API 근거, 나머지는 실측·관행)

## 1. GitHub 기본 검색 대상은 Name / Description / Topics 뿐

- 저장소 기본 검색(`q=<term>`)에 매칭되는 메타데이터는 **이름, About description, topics** 세 가지다 (D4).
- **README 본문/H1은 기본 검색에 포함되지 않는다.** README 키워드를 검색에 쓰려면
  `q=<term> in:readme` 한정자를 명시해야 한다. 즉 README 최적화는
  GitHub 내부 검색이 아니라 **Google/Bing·GPTBot/ClaudeBot/PerplexityBot 스니펫과
  방문자 전환**을 목표로 삼아야 한다.
- 따라서 이름은 이미 자산(`q=herdr-team`에서 노출)이지만, description/topics가 비면
  조합 질의(`herdr team setup`)에서 탈락한다. 메타데이터 공백은 곧 검색 매칭 0이다.
- 이름 기반 노출과 메타데이터 기반 노출은 별개 진입로이므로 둘 다 채워야 한다.

## 2. Topics: 최대 20개 · PUT replace-all이 add-only보다 낫다

- topics 규칙 (D1): 소문자/숫자/하이픈만, 태그당 50자 이하, **저장소당 최대 20개**.
- topics 교체 API는 `PATCH`가 아니라 **`PUT /repos/{owner}/{repo}/topics`** 이며
  본문 키는 `names[]` 이다 (D10). GET 응답의 `.names`로 키 이름을 실측 확인했다.
- add-only(`gh repo edit --add-topic`) 대비 replace-all의 장점:
  - **원자성**: 부분 적용 상태가 남지 않는다.
  - **호출 1회**: 20개를 N회 루프가 아니라 1회 요청으로 수렴.
  - **멱등/선언적 수렴**: 스크립트의 `TOPICS` 세트가 곧 원격 상태라 세트 변경 시 드리프트가 없다.
    (add-only는 현재 스크립트가 remove를 호출하지 않아, 세트에서 뺀 태그가 잔존한다.)
- 20개 상한과 정규식은 **원격 호출 전 사전 guard**로 막는다(초과/오타로 기존 세트를 날리는 사고 예방).

## 3. Description: 157자 키워드 전진배치(keyword front-loading)

- description은 검색 결과·About 카드에서 잘려 노출될 수 있으므로 **핵심 키워드를 앞에** 둔다.
- 본 저장소 적용값(157자): 앞 24자에 `Multi-agent orchestration`을 두고,
  이어서 `AI coding agents`, `planner/worker/reviewer`, `herdr terminal multiplexer`,
  `TDD`·`solo-app`·`small-biz` 순으로 배치.
- ⚠️ **160자 하드리밋은 공식 문서에 없는 커뮤니티 스니펫 관행**(D9)이다. 157자는
  관행 하한 내 안전값일 뿐, 초과해도 저장은 되지만 검색 결과에서 잘릴 수 있다.

## 4. 본 저장소 적용값과 측정 방법

- **Description**: `Multi-agent orchestration for AI coding agents: one-command planner/worker/reviewer crew on the herdr terminal multiplexer. TDD, solo-app, small-biz presets.` (157자)
- **Topics(20)**: `ai-agents multi-agent orchestration agent-orchestration coding-agents ai-agent opencode claude-code codex herdr terminal-multiplexer terminal tui cli developer-tools automation tdd shell windows wsl`
- **homepage**: Release 발행 후 `https://github.com/harry81/herdr-team/releases` (Windows zero-terminal 약속과 직결). Release 전 과도기는 repo 루트.
- **Release/Tag**: `v0.1.0` 태그 + Release 발행, asset 명을 `build-zip.sh` 기본 산출물 패턴(`herdr-team-YYYYMMDD.zip`)과 일치시켜 README 약속과 정합화.
- 적용 스크립트: `scripts/repo-meta.sh` (description은 `gh repo edit`, topics는 PUT 1회. `--dry-run`은 명령·글자수·토픽수 출력).

측정 커맨드:

```bash
# 메타데이터 반영 확인
gh api repos/harry81/herdr-team --jq '{description,topics,homepage}'
gh api repos/harry81/herdr-team --jq '.topics|length'      # 목표 20

# 조합 검색 노출 (before: total_count=1, 미노출)
curl -s "https://api.github.com/search/repositories?q=herdr+team+setup" | jq '.total_count,.items[].full_name'

# topic 브라우징 포함 여부 (total_count만 보면 항상 통과하므로 포함을 단언)
gh api "search/repositories?q=topic:herdr" --jq '.items[].full_name | select(.=="harry81/herdr-team")'

# head meta description (before: generic 폴백)
curl -s https://github.com/harry81/herdr-team | grep -o '<meta name="description"[^>]*>'
```

- 검색 인덱스 반영에 수 시간이 걸릴 수 있어 **적용 24h 후 재측정**을 권장한다.
- 이름 검색 순위(`q=herdr-team`)는 회귀 감시 지표로 고정한다.
