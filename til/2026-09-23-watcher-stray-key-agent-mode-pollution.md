# TIL: herdr-watcher AUTO-ALLOW stray 키 주입으로 인한 agent 모드 오염

- **날짜**: 2026-09-23
- **범위**: `bin/herdr-watcher`, `tests/test_watcher.sh`, `.github/workflows/ci.yml`
- **관련 TIL**: [`2026-09-19-herdr-agent-wait-syntax-and-ghost-process-unblock.md`](2026-09-19-herdr-agent-wait-syntax-and-ghost-process-unblock.md), [`2026-09-14-herdr-watcher-and-taskmanager-separation.md`](2026-09-14-herdr-watcher-and-taskmanager-separation.md), [`2026-09-23-no-redundant-wait-after-prompt-wait.md`](2026-09-23-no-redundant-wait-after-prompt-wait.md)

---

## 1. 문제 현상

- Worker pane 의 footer agent 표시가 `Worker` 가 아니라 `Plan` 등으로 순환되어, primary agent 모드가 오염되고 편집이 불가능해졌다.
- watcher 로그에 30초 내 동일 팝업에 대한 `[AUTO-ALLOW] ... 승인 키(tab+enter) 전송` 이 5회 이상 반복 발사되었다.
- 팝업이 이미 닫힌 뒤에도 `tab` 이 계속 주입되어 opencode TUI 의 primary agent 순환이 발생했다.

---

## 2. 근본 원인 — 3중 결함 (수정 전 `bin/herdr-watcher`)

1. **blind blocked 경로**: `status == "blocked"` 이면 화면 확인 없이 곧바로 전송 (수정 전 :147-153, `not is_blocked` 조건 때문에 blocked 경로가 화면검사를 건너뜀).
2. **무디바운스**: 인터벌(기본 5초)마다 동일 팝업에 재전송. 팝업이 닫혔으면 전부 stray.
3. **무조건 tab**: `herdr pane send-keys <pane> tab enter` 고정 (수정 전 :95-101). `tab` 은 opencode TUI 에서 **primary agent 순환 키**라, 다이얼로그가 없으면 모드 오염을 일으킨다.

---

## 3. 메커니즘

- 팝업은 `Allow once / Allow always / Reject` + `⇆ select` + `enter confirm` 구조이며 기본 선택은 첫 항목(Allow once)로 보인다.
- watcher 는 상태(`blocked`)만 보고 키를 쏘았고, 화면 실확인/쿨다운/상한이 없어 팝업 수명보다 오래 `tab` 을 재주입했다.
- 팝업이 닫힌 뒤의 `tab` 은 다이얼로그가 아닌 primary agent 선택에 소비되어 footer 가 `Worker` → `Plan` 등으로 순환했다.

---

## 3.1 라이브 게이트 실패와 오탐 경로 (수정 라운드 2, 2026-09-23)

신규 코드로 htw 를 재기동한 라이브 게이트에서 **다시 Plan 모드 격하**가 발생했다(실패를 숨기지 않고 기록).

`wV:pB` 로그:
```
[11:35:26] [AUTO-ALLOW] ht-orchestrator (wV:p8) 팝업 확인 -> 승인 키(enter) 전송
[11:35:36] [AUTO-ALLOW] ht-orchestrator (wV:p8) 팝업 확인 -> 승인 키(tab enter) 전송
[11:35:46] [AUTO-ALLOW] ht-orchestrator (wV:p8) 팝업 확인 -> 승인 키(enter) 전송
[11:35:46] 상태 전이: [ht-orchestrator] working -> idle
[11:35:56] [AUTO-ALLOW] ht-orchestrator (wV:p8) 팝업 확인 -> 승인 키(tab enter) 전송
```

근본 원인(수정 라운드 1 이 남긴 설계 결함):
- `check_permission_screen` 은 "Permission required"/"Allow once" **부분문자열 판정**이다. Orchestrator 트랜스크립트에는 그 문자열이 **사람이 읽는 텍스트로 영구히 존재**(리뷰 보고서 인용 등)한다.
- 따라서 진짜 팝업이 아닌데도 popup=True 오탐 → 어떤 키를 눌러도 마커가 사라지지 않음 → `retry_after`(10초) 경과 후 fallback(`tab enter`)이 반드시 발화 → `tab` 이 primary agent 순환 → Plan 격하 재발.
- 해당 pane 의 herdr status 는 `working` 이었다(진짜 권한 팝업일 때만 herdr 이 `blocked` 로 표시).

수정(수정 라운드 2):
- **트리거를 OR 에서 AND 로**: `blocked = (status == "blocked")`; **`blocked` AND popup 일 때만 전송**. popup 만 있고 working 이면 오탐(트랜스크립트 텍스트 등)으로 간주해 episode 리셋 후 미전송.
- **fallback fail-closed**: `--fallback-keys` 기본값을 `""`(비활성)로 변경 → `tab` 은 기본 설정에서 **절대 자동 발화하지 않음**. `tab` 이 필요한 엔진만 `--fallback-keys "tab enter"` 로 명시 옵트인.
- live 에서 `enter` 가 빈 프롬프트를 제출해 턴이 강제 종료된 관측도 있었다 → enter 단독 승인은 여전히 미검증(가설).

**알려진 한계(YAGNI, 이번에 미해결)**: "팝업은 실제로 뜨는데 herdr status 가 `blocked` 로 바뀌지 않는 엔진" 은 AND 게이트에서 미탐지된다. 새 탐지 방식(`--source detection` 등)은 도입하지 않았고, 해당 엔진은 `--allow-on-blocked` 레거시 옵트인으로만 대응한다(후속 이슈 후보).

---

## 4. 수정 설계 (edge-triggered)

정상 동작 목표: **팝업 등장 → (쿨다운 통과?) → 전송 직전 재확인 → 승인 키 전송 → 사후 재확인**

- 전송 직전 `check_permission_screen(name)` 재확인 실패 시 전송 취소(race 제거, `attempts` 리셋).
- 사후 확인에서 팝업이 사라졌으면 episode 종료(`attempts=0`), 재전송 금지.
- 팝업 소멸 시 episode 리셋, 쿨다운(`last`)은 보존 → flapping 억제.
- `(팝업 유지 && attempts<max && 쿨다운 경과)` 이면 fallback 키 1회.

debounce 상태:
```python
sent_state = { "<agent>": {"attempts": int, "last": float} }  # attempts=현재 팝업 episode 전송 횟수, last=마지막 전송 시각(팝업 소멸해도 보존)
```

핵심 변경 (`bin/herdr-watcher`):
- 승인 조건: `status == "blocked"` **AND** 화면 팝업 확인 (AND 게이트; 수정 라운드 2).
- `send_keys()` / `unblock_agent(pane_id, name, keys)` / `handle_permission(...)`: 기본은 **enter 단독**으로 stray tab 제거.
- CLI: `--approve-keys`(기본 `enter`; 빈 값이면 enter 대체), `--fallback-keys`(기본 `""`=**비활성**, `tab` 은 명시 옵트인 시에만), `--retry-after`(기본 10초), `--max-attempts`(기본 2, `--allow-on-blocked` 경로에도 상한 적용), `--allow-on-blocked`(화면 확인 불가 엔진 전용 레거시, 기본 off).
- AUTO-ALLOW 기능 자체는 유지: 팝업 확인 + blocked 시 반드시 1차 전송, enter 불충분 엔진은 (옵트인된) fallback 1회, `--no-auto-allow` 불변.
- quirk(문서화): 전송 직전 재확인(call#2) 실패 시 `attempts=0` 리셋이 진행 중 fallback 1회를 다음 루프에서 1차(approve)로 되돌릴 수 있다(기능 보존 위해 동작 유지).

---

## 5. stuck 원인 2개 구분 (진단법)

| 원인 | 정체 | 진단 |
|---|---|---|
| (i) `prompt --wait` 직후 중복 `agent wait` | 문서/행동규칙 (이슈 #1) | `ps` 에 `herdr agent wait` 프로세스가 물려 있으면 이슈 #1 |
| (ii) watcher stray 키 agent 모드 오염 | 본 이슈 (오탐 경로 포함) | footer agent 표시가 `Worker`/`Reviewer` 가 아니면(예: `Plan`) 본 결함 |

---

## 6. `clean_stuck_waits` 불변

`clean_stuck_waits`(수정 전 :104-119)는 자가치유 안전망이므로 **미변경**. 본 이슈의 수정 대상이 아니다.

---

## 7. 검증

신규 `tests/test_watcher.sh`(fake herdr 셰임 + `HERDR_FIX` fixture, python3 부재 시 SKIP), 케이스 a~i:

- a) 팝업 없음 + blocked → 전송 0 (stray 제거, 회귀 핵심)
- b) 팝업 확인 + blocked → 1회 승인, 키=enter, tab 미포함
- c) 팝업이 승인 후 소멸 → 정확히 1회 (무디바운스)
- d) 팝업 유지 + `--fallback-keys "tab enter"` **옵트인** → 최대 2회, 2번째=tab enter
- e) `--no-auto-allow` → 미전송
- f) `--approve-keys "right enter"` → 키 시퀀스 반영
- g) `--allow-on-blocked` → 레거시 복원(1회)
- h) **status=working + 화면 마커(오탐) → 전송 0건** (라이브 장애 직접 재현; AND 게이트)
- i) blocked + popup 유지 + 기본 fallback(`--retry-after 0`) → **enter 만 1회, tab 0건** (fail-closed)

결과: `bash tests/test_watcher.sh` → `RESULT: PASS=14 FAIL=0`.
회귀: `tests/test_install.sh`(43) / `tests/test_preset.sh`(320) / `tests/test_windows_launcher.sh`(63) 전부 `FAIL=0`.

---

## 8. 엔진 무관 & 운영 주의

- 키 의미 하드코딩 금지: 승인/대체 키는 CLI(`--approve-keys`/`--fallback-keys`)로 분리 → 엔진 무관.
- **enter 단독 승인 불확실성(미검증)**: 라이브 팝업의 선택 하이라이트는 `herdr agent read`(텍스트)로 검증 불가하므로 "기본 선택 = Allow once" 는 **가설**이다. 실제 라이브 게이트에서 `enter` 가 빈 프롬프트를 제출해 턴이 강제 종료된 관측이 있었다. opencode 가 Reject 를 기본으로 하면 enter 가 오거부할 수 있다 → `--allow-on-blocked` 로 완화, 머지 전 수동 검증 권장.
- **fallback(tab) 기본 비활성(fail-closed)**: `tab` 은 opencode primary agent 순환 키이므로 기본 설정에서 자동 발화하지 않는다. 필요한 엔진만 `--fallback-keys "tab enter"` 로 옵트인.
- **known limitation**: 팝업이 뜨는데 herdr status 가 `blocked` 로 안 바뀌는 엔진은 AND 게이트에서 미탐지. 새 탐지 방식은 도입하지 않았고 `--allow-on-blocked` 로만 대응(후속 이슈 후보).
- 화면 텍스트 마커는 opencode 기준이므로 타 엔진은 `--allow-on-blocked` 또는 마커 확장이 필요(후속 이슈 후보).
- ⚠️ 살아있는 htw 는 구 코드 프로세스다. 파일 수정만으로 반영되지 않으며 **재시작은 운영(ops) 범위(vigilance/PM 승인 사항)** 이다. worker 는 코드/테스트만 수정한다.
