# Devops

DevOps 수업 실습 기록(6·7주차 자료와 방명록 앱)을 모아 둔 저장소입니다. 6주차에는 Dockerfile 작성과 이미지 배포를, 7주차에는 Docker Compose로 여러 컨테이너를 함께 실행하는 실습을 다루며, 두 실습에 사용한 Flask 방명록 앱의 소스도 함께 들어 있습니다.

## 내용

### 6주차: Dockerfile과 이미지 배포
- `week06/README.md`: 실습 보고서. 이미지 주소(ghcr.io의 v1·v2), 다른 이미지를 받아 실행한 결과, Dockerfile 각 줄의 역할, 빌드 캐시(`CACHED`) 로그, 설정을 넣는 세 가지 방법(코드 기본값, `ENV`, `docker run -e`)의 차이를 정리했습니다.

### 7주차: Docker Compose
- `week07/README.md`: 실습 보고서. `docker compose ps` 결과(healthy 상태), web을 3개로 늘린 뒤 Nginx를 거친 요청 분산 결과, `down`과 `down -v`의 차이, `.env`를 Git에 올리지 않는 이유를 정리했습니다.

### 방명록 앱 (`guestbook/`)
- `app.py`, `templates/index.html`, `requirements.txt`: Flask로 만든 방명록 앱. 이름과 메시지를 남기고, 방문자 수와 호스트명을 화면에 보여 줍니다. `REDIS_HOST` 환경변수가 있으면 Redis에, 없으면 메모리에 저장합니다.
- `Dockerfile`: 앱 이미지를 만드는 파일(`python:3.12-slim` 기반, 일반 사용자 `appuser`로 실행).
- `Dockerfile.multistage`: 빌드 단계와 실행 단계를 나눠 이미지 용량을 줄이는 멀티스테이지 예제.
- `Dockerfile.custom`: `ghcr.io/makyraen/inhatc-devops-guestbook:v1` 이미지를 베이스로 `APP_TITLE`, `THEME_COLOR` 환경변수를 지정하는 짧은 Dockerfile입니다(미완성 형태로, 그대로는 빌드되지 않을 수 있습니다).
- `compose.yaml`: `nginx`, `web`, `redis` 세 서비스 구성. `web`과 `redis`에는 healthcheck가, `redis`에는 `redis-data` 볼륨이 설정되어 있습니다.
- `nginx.conf`: 80 포트로 들어온 요청을 `web` 서비스(5000 포트)로 넘기는 리버스 프록시 설정입니다. `compose.yaml`이 호스트의 8080 포트를 nginx의 80 포트에 연결합니다.
- `.env.example`, `.dockerignore`: 환경변수 예시 파일과 이미지 빌드 시 제외할 파일 목록.
- `README.md`: 앱 설명, 실행 방법, 엔드포인트, 환경변수 표.

### 기타
- `images/`: 실행 화면 캡처 이미지. `localhost:8091`, `8092`, `8093` 세 주소에 각각 `Hi`, `Hello`, `Bonjour`가 표시된 브라우저 화면입니다.
- `.gitignore`: `.env`를 저장소에서 제외합니다.

## 참고

- Compose로 실행하려면 `guestbook/` 폴더에서 `.env.example`을 `.env`로 복사해 `REDIS_PASSWORD` 값을 정한 뒤 `docker compose up -d`를 실행하고 `http://localhost:8080`에 접속합니다. `compose.yaml`은 `REDIS_PASSWORD`가 없으면 오류를 내도록 되어 있습니다.
- 실제 `.env` 파일은 `.gitignore`로 제외되어 있어 저장소에 없습니다.
- 웹 컨테이너를 3개로 늘리는 명령은 `docker compose up -d --scale web=3`이며, 결과는 `week07/README.md`에 있습니다.
- Docker만으로 단독 실행하는 방법(빌드, 실행, ghcr.io 업로드, 멀티스테이지 빌드)은 `guestbook/README.md`에 있습니다.

## 화면 캡처

<img width="717" height="282" alt="스크린샷 2026-09-30 121609" src="https://github.com/user-attachments/assets/14dc01f1-bbf2-4445-8de5-4ccafbec98a1" />
