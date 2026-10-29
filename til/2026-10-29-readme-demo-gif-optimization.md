# Today I Learned: README 데모 미디어 에셋 최적화 및 문서 임베딩

- **날짜**: 2026-10-29
- **주제**: 오픈소스 README 데모 시각화 (Video to GIF 변환 및 파일 크기/해상도 밸런싱)

---

## 1. 배경 및 목적
- CLI/TUI 기반 멀티에이전트 오케스트레이션 도구(`herdr-team`)의 실행 화면을 사용자에게 직관적으로 보여주기 위해 README(`README.md`, `README.ko.md`)에 실제 터미널 녹화 데모를 추가.

## 2. 핵심 이론 및 기법

### 2.1 GIF 팔레트 최적화 (`ffmpeg palettegen` / `paletteuse`)
- 일반적인 비디오를 GIF로 단순 변환(`ffmpeg -i input.mp4 output.gif`)하면 256색 고정 기본 팔레트로 인해 심한 밴딩(Color Banding)과 파일 크기 폭증이 발생함.
- 2단계 파이프라인 필터(`palettegen` + `paletteuse`) 적용:
  ```bash
  ffmpeg -y -i demo.mp4 -vf "fps=10,scale=960:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer" demo.gif
  ```
  - **`fps=10`**: 터미널 TUI 변화 속도를 부드럽게 유지하면서 프레임 수 66% 절감.
  - **`scale=960:-1:flags=lanczos`**: 고품질 Lanczos 리스케일링으로 터미널 텍스트 가독성 보존.
  - **`max_colors=128` & `dither=bayer`**: 콘솔 텍스트의 균일 배경색 특성을 살려 색상 수를 제한하고 격자 디더링으로 파일 용량을 극적으로 최적화 (~1.0MB 달성).

### 2.2 GitHub README 미디어 배치 모범 사례
- 원본 MP4 비디오(`docs/assets/demo.mp4`)와 자동 재생/호환성용 경량 GIF(`docs/assets/demo.gif`)를 함께 에셋 디렉터리에 보관.
- 마크다운 상단 아키텍처 다이어그램 및 파이프라인 뷰 바로 앞 `How it looks` 섹션에 배치하여 첫 진입 시 시각적 임팩트 제공.
