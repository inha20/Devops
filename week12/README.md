# Week 12 실습 보고서: GitHub Actions CI & 브랜치 보호

## 1. CI 파이프라인 구성 (`.github/workflows/build.yml` & `guestbook/tests/test_app.py`)
- **적용 PR**: PR #2 (`feature/ci-setup` → `main` 머지 커밋 `a18e437`, 2026-11-18)
- **워크플로 흐름**:
  1. `actions/checkout@v4` → `actions/setup-python@v5` (`3.12`)
  2. **린트 (`ruff check . --select=E9,F`)**: 실행 전 문법 오류(E9) 및 정의되지 않은 변수/오타(F) 검사
  3. **단위 테스트 (`python -m unittest discover -s tests -v`)**: `REDIS_HOST=''`(메모리 모드)로 `/healthz` 응답 및 `/add` → `/api/entries` CRUD 검증
  4. **멀티 플랫폼 이미지 빌드 & 푸시 (`docker/build-push-action@v6`)**: `linux/amd64,linux/arm64` 빌드 후 `main` 브랜치 push 시에만 `ghcr.io/inha20/guestbook:<short-sha>` 및 `:latest` 게시 (PR 단계에서는 `push: false`로 검증만 수행)

---

## 2. 실습: 빨간 X(실패) → 수정 → 초록 ✓(성공) 검증 기록

### (1) 문법 오류 차단 (`def broken(:`)
- **PR #3 (`feature/ci-errors`) / Run `44212682500` (실패, 12s)**:
  ```text
  invalid-syntax: unexpected EOF while parsing
     --> app.py:136:14
      |
  135 |     app.run(host="0.0.0.0", port=PORT)
  136 | def broken(:
      |             ^

  Found 2 errors.
  ##[error]Process completed with exit code 1.
  ```
- **원인 및 조치**: 잘못 추가한 `def broken(:` 삭제 후 재푸시 → Run `44212779167`에서 초록 ✓ (`1m10s`) 복구.

### (2) 린트 검사로 런타임 오타 조기 탐지 (`print(APP_TITL)`)
- **PR #3 (`feature/ci-errors`) / Run `44213068485` (실패, 11s)**:
  ```text
  89 |     visits = incr_visits()
  90 |     print(APP_TITL)
     |           ^^^^^^^^
  91 |     return render_template(

  Found 1 error.
  ##[error]Process completed with exit code 1.
  ```
- **핵심 원리**: `python3 -m compileall` 문법 검사는 통과하는 오타(`APP_TITLE` → `APP_TITL`)를 `ruff`가 코드를 실행하지 않고도 정적 분석 단계에서 즉시 차단해 운영 중 `HTTP 500` 장애를 예방함.

### (3) 단위 테스트로 API 회귀 오류 탐지 (`/healthz` 500 반환)
- **PR #3 (`feature/ci-errors`) / Run `44213320469` (실패, 16s)**:
  ```text
  File "/home/runner/work/Devops/Devops/guestbook/tests/test_app.py", line 14, in test_health
    self.assertEqual(response.status_code, 200)
  AssertionError: 500 != 200
  ----------------------------------------------------------------------
  Ran 2 tests in 0.048s
  FAILED (failures=1)
  ##[error]Process completed with exit code 1.
  ```
- **핵심 원리**: 문법·린트를 모두 통과한 코드라도 의도치 않게 `/healthz` 상태코드를 깨뜨리면 `unittest`가 실패(종료 코드 1)하여 Kubernetes Liveness Probe 무한 재시작 장애로 이어지기 전에 차단함. 이후 원복하여 Run `44213496763`에서 통과.

---

## 3. `main` 브랜치 보호 규칙(Branch Protection) 적용 및 검증
- **설정 내역 (`Settings > Branches > main`)**:
  - `Require a pull request before merging` 활성화 (`Require approvals: 0`)
  - `Require status checks to pass before merging` 활성화 → **`build`** 체크 필수 지정
  - `Do not allow bypassing the above settings` (`enforce_admins: true`) 적용
- **깨진 코드 PR 차단 검증 (PR #4 `feature/broken-test`)**:
  - `def broken2(:`를 포함한 커밋 푸시 시 Run `44214047735`이 `exit code 1`로 실패하며 GitHub PR의 Merge 버튼이 비활성화됨을 확인.
  - 오류 수정 후 재푸시하여 Run `44214227378` 통과(`59s`) 후 Squash Merge(`5a32c81`) 완료.

---

## 4. 핵심 개념 정리
- **CI vs CD**: CI는 코드 통합 시 자동 검사(린트·테스트·빌드)로 깨진 코드 유입을 막고, CD는 검증된 산출물을 배포 가능한 상태로 유지(Delivery)하거나 운영에 자동 반영(Deployment)합니다.
- **종료 코드(Exit Code) 기준**: GitHub Actions는 화면 출력 문구가 아니라 명령어의 종료 코드(`0` = 성공, `0 이외` = 실패)로 단계 통과 여부를 판단합니다.
- **`latest` 태그 대신 커밋 해시 사용 이유**: `latest`는 계속 덮어써지므로 장애 시 이전 버전 추적이 어렵지만, 짧은 커밋 SHA(`a18e437`, `8825180`) 태그는 어떤 커밋에서 빌드된 이미지인지 정확히 추적·롤백할 수 있습니다.
