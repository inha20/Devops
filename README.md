# Devops

인하공전 DevOps 수업 실습 기록(2~7주차) 및 방명록 앱 소스코드를 모아둔 저장소입니다.

## 주차별 실습 내용

### 2주차: 실습 환경 구축과 버전 관리 기초
- [`week02/README.md`](week02/README.md): WSL2 Ubuntu 환경 세팅, 가상화(베어메탈, VM, 컨테이너) 비교, Git 기초 명령어와 GitHub CLI(`gh`) 연동 실습 정리.

### 3주차: 셸 스크립팅과 자동화 기초
- [`week03/README.md`](week03/README.md): 반복 작업을 줄이기 위한 셸 스크립트 작성법, Shebang, 실행 권한(`chmod u+x`), `cd "$(dirname "$0")"` 관용구, 환경변수 및 if 조건문 실습 정리.

### 4주차: 자동화와 협업 & 네트워크 기초
- [`week04/README.md`](week04/README.md): for문과 파이프라인(`|`), `grep`을 이용한 텍스트/파일 제어, IP와 포트 개념, 로컬 웹 서버 테스트, Windows Zone.Identifier 문제 해결.

### 5주차: 도커 기초 및 Nginx 다중 컨테이너 실행
- [`week05/README.md`](week05/README.md): Docker 기본 명령어, GitHub Issue(#1) 기반 협업 흐름, 포트가 서로 다른 3개의 Nginx 컨테이너(8091, 8092, 8093) 띄우고 `index.html` 수정 실습.

### 6주차: Dockerfile과 이미지 배포
- [`week06/README.md`](week06/README.md): 이미지 주소 구조(ghcr.io의 v1·v2), 다른 이미지 받아 실행하기, Dockerfile 각 줄의 역할 설명, 빌드 캐시(`CACHED`) 확인, 환경변수 주입 방법 차이.

### 7주차: Docker Compose
- [`week07/README.md`](week07/README.md): `compose.yaml` 기반 멀티 컨테이너 제어, `docker compose ps` 결과(healthy 상태), `web=3` 스케일 아웃 후 Nginx 로드밸런싱 응답 확인, `down`과 `down -v`의 차이.
- [`week07/keep_web_replicas.sh`](week07/keep_web_replicas.sh): [호기심 문제] `web=3` 컨테이너 개수를 상시 유지해 주는 셸 모니터링 스크립트.

---

### 방명록 앱 (`guestbook/`)
- `app.py`, `templates/index.html`, `requirements.txt`: Flask 방명록 앱. 이름/메시지를 남기면 방문자 수와 호스트명을 보여줌. Redis가 있으면 Redis에, 없으면 메모리에 저장.
- `Dockerfile`: 앱 이미지 빌드 파일(`python:3.12-slim` 베이스, 일반 사용자 `appuser`로 실행).
- `Dockerfile.multistage`: 빌드와 실행 단계를 분리한 멀티스테이지 예제.
- `compose.yaml`: `nginx`, `web`, `redis` 3개 서비스 구성. healthcheck 및 redis-data 볼륨 연결.
- `nginx.conf`: 80 포트로 들어온 요청을 `web` 서비스(5000 포트)로 분산 전달하는 리버스 프록시 설정.
- `.env.example`, `.dockerignore`: 환경변수 샘플 파일 및 이미지 빌드 제외 목록.
- `README.md`: 앱 설명, 실행 방법, 환경변수 표.

### 기타
- `images/`: 실행 화면 캡처 이미지. `localhost:8091`, `8092`, `8093` 세 주소에 각각 `Hi`, `Hello`, `Bonjour`가 표시된 브라우저 화면.
- `.gitignore`: `.env` 및 불필요한 메타데이터 파일 제외.

## 실행 방법 (Compose)
1. `guestbook/` 폴더에서 `.env.example`을 복사해 `.env`를 만듭니다 (`REDIS_PASSWORD` 입력 필요).
2. `docker compose up -d` 실행 후 브라우저에서 `http://localhost:8080` 접속.
3. 웹 컨테이너를 3개로 늘리려면: `docker compose up -d --scale web=3`

## 화면 캡처

<img width="717" height="282" alt="스크린샷 2026-09-30 121609" src="https://github.com/user-attachments/assets/14dc01f1-bbf2-4445-8de5-4ccafbec98a1" />
