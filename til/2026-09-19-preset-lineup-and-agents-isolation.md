# 2026-09-19: 프리셋 5종 확장 및 에이전트 문서 폴더 격리 아키텍처

## 1. 배경 및 문제 의식
초기 `herdr-team`은 소프트웨어 개발(`dev`) 중심의 4인 팀 체제(`orchestrator`, `planner`, `worker`, `reviewer`)로 구성되어 있었다.
그러나 사용자의 실제 목적은 개발자뿐만 아니라 1인 연구자, 소상공인(자영업자), 로컬 마케터, 콘텐츠 크리에이터 등으로 다양하다.

또한 동일한 프로젝트 경로에서 프리셋을 변경(예: `dev` → `mkt`)할 때 기존의 단일 `agents/` 구조는 다음과 같은 구조적 문제를 안고 있었다:
1. **역할 정의 덮어쓰기 또는 누락**: `--force`가 없으면 기존 `dev`의 `AGENTS.md`와 역할 지침이 그대로 남아, `mkt` 팀인데도 reviewer가 코드 빌드와 테스트를 요구하는 치명적인 역할 혼선 발생.
2. **커스텀 프롬프트 유실**: `--force`를 주면 사용자가 해당 프로젝트에 맞게 공들여 튜닝한 에이전트 지침이 영구 소실됨.

---

## 2. 해결 방안: 5대 라인업 & 폴더 격리(Namespace Isolation)

### 2.1 사용자 목적별 5대 프리셋 라인업
기존 중복 성격이었던 `app`(1인 앱)을 `dev`로 통합(Planner에 UX/와이어프레임 명세 의무 포함)하고, 실사용 목적 중심의 5대 라인업으로 정비했다:
1. **`dev`** — 소프트웨어 개발 & MVP (`orchestrator`, `planner`, `worker`, `reviewer`)
2. **`research`** — 심층 조사 & 지식 탐색 (`orchestrator`, `planner`, `researcher`, `reviewer`)
3. **`biz`** — 소상공인 사업 운영/행정/지원사업 (`orchestrator`, `planner`, `researcher`, `reviewer`)
4. **`mkt`** — 로컬 & SNS 마케팅 (`orchestrator`, `planner`, `researcher`, `reviewer`)
5. **`creator`** — 콘텐츠 창작 & 출판 (`orchestrator`, `planner`, `worker`, `reviewer`)

### 2.2 폴더 격리(`agents/<preset>/`) 및 무손실 스위칭(Lossless Switching)
각 프리셋의 역할 문서를 물리적으로 격리하여 저장한다:
```text
프로젝트 루트/
├── AGENTS.md                  <-- 현재 활성 프리셋의 뷰 (단순 복사본)
├── .herdr-team/preset         <-- 활성 프리셋 상태 기록 (예: mkt)
└── agents/
    ├── dev/                   <-- dev 전용 지침 (보존됨)
    │   ├── {prefix}-planner.md
    │   ├── {prefix}-worker.md
    │   └── {prefix}-reviewer.md  (코드/빌드/TDD 검증)
    └── mkt/                   <-- mkt 전용 지침 (독립 보존)
        ├── {prefix}-planner.md
        ├── {prefix}-researcher.md
        └── {prefix}-reviewer.md  (카피/광고법/팩트체크 검증)
```

- **Write-back 동기화**: 프리셋 전환 시 현재 루트 `AGENTS.md`의 수정사항을 직전 프리셋 폴더로 안전하게 동기화(write-back)한 뒤 새 프리셋 문서를 루트로 복사.
- **Cross-Platform 안전성**: Windows 환경의 권한 문제로 실패할 수 있는 심볼릭 링크(`ln -s`) 대신, **파일 복사 및 상태 파일 동기화** 방식으로 처리하여 Windows/macOS/Linux 100% 호환 보장.
- **Opencode Stale Prune**: 전환 시 불필요해진 구 프리셋의 primary agent 정의(`.opencode/agents/`)를 prune하고 활성 역할만 깔끔하게 등록.

---

## 3. 다형적 Reviewer (Polymorphic Reviewer Pattern)
이름은 동일하게 `reviewer`이지만 도메인에 따라 검증 의무가 근본적으로 분기된다:
- **코드 프로젝트(`dev`)**: 직접 CLI를 통해 빌드(`build`), 정적분석(`lint`), 단위/통합/E2E 테스트 실행 로그를 첨부해야만 `[APPROVE]` 가능.
- **비코드/콘텐츠 프로젝트(`mkt`, `creator`, `biz`, `research`)**:
  - **교정/교열**: 맞춤법, 가독성, 문장 호흡
  - **컴플라이언스**: 표시광고법, 금칙어, 과장/허위 표현 검증
  - **팩트체크**: 모든 주장과 수치의 원천 출처(URL, 논문, 공공데이터) 신뢰성 교차 검증

---

## 4. 메타문자 치환 안전성 (Sed Replacement Escaping)
템플릿 변수 치환(`subst_tpl`) 시 `{{PRESET}}` 치환값에 `&`, `/`, `\` 등의 특수문자가 포함될 경우 sed에서 의도치 않은 메타문자로 해석되어 치환이 누락되는 현상이 발생할 수 있다.
- **해결책**:
  ```bash
  p=$(printf "%s" "$PREFIX" | sed -e 's/[\/&]/\\&/g')
  r=$(printf "%s" "$PRESET" | sed -e 's/[\/&]/\\&/g')
  sed -e "s/{{PREFIX}}/$p/g" -e "s/{{PRESET}}/$r/g" "$1"
  ```
- TDD Red→Green 테스트(`subst_preset_ampersand_escaping`)를 통해 회귀 방지 보장.

---

## 5. 결론
이로써 단일 레포지토리 내에서 개발, 비즈니스 계획, 마케팅, 리서치 등을 자유롭게 왕복하며 작업할 수 있는 강력한 멀티도메인 오케스트레이션 기반이 완성되었다.
