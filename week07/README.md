# Week 07 실습 보고서: 도커 컴포즈 (Docker Compose)

## 1. `docker compose ps` 결과 (healthy 상태 포함)

다중 컨테이너 환경(Nginx, Web 3개 인스턴스, Redis)을 구성하고 모든 서비스의 Healthcheck 통과 및 정상 기동을 확인했습니다.

```text
NAME                IMAGE            COMMAND                  SERVICE   CREATED          STATUS                    PORTS
guestbook-nginx-1   nginx:alpine     "/docker-entrypoint.…"   nginx     22 seconds ago   Up 8 seconds              0.0.0.0:8080->80/tcp, [::]:8080->80/tcp
guestbook-redis-1   redis:7-alpine   "docker-entrypoint.s…"   redis     22 seconds ago   Up 21 seconds (healthy)   6379/tcp
guestbook-web-1     guestbook-web    "python app.py"          web       22 seconds ago   Up 15 seconds (healthy)   5000/tcp
guestbook-web-2     guestbook-web    "python app.py"          web       22 seconds ago   Up 15 seconds (healthy)   5000/tcp
guestbook-web-3     guestbook-web    "python app.py"          web       22 seconds ago   Up 14 seconds (healthy)   5000/tcp
```

- **Healthcheck 동작 확인**:
  - `redis`: `redis-cli -a ${REDIS_PASSWORD} ping` 명령을 주기적으로 실행하여 PONG 응답을 통해 준비 상태 검증
  - `web`: `python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/readyz')"` 점검을 통과한 후 Healthy 상태로 전이
  - 의존성 조건(`depends_on`의 `condition: service_healthy`)에 따라 Redis 준비 완료 후 Web이 시작되고, Web 준비 완료 후 Nginx가 기동됨.

---

## 2. Scale 적용 후 각 웹 컨테이너 호스트명(컨테이너 ID) 변경 결과

`docker compose up -d --scale web=3`으로 웹 애플리케이션 컨테이너를 3대로 수평 확장(Scale-out)하고 Nginx 리버스 프록시를 통해 로드 밸런싱이 동작함을 확인했습니다.

### 컨테이너 목록 (`docker ps`)
```text
CONTAINER ID   NAMES               STATUS
29103a927ef2   guestbook-nginx-1   Up 12 seconds
e5783db29a70   guestbook-web-1     Up 18 seconds (healthy)
d3e571d5b586   guestbook-web-2     Up 18 seconds (healthy)
27c24db15927   guestbook-web-3     Up 18 seconds (healthy)
d420df4e148f   guestbook-redis-1   Up 24 seconds (healthy)
```

### 브라우저/요청별 Pod/Host 응답 변화 (`curl http://localhost:8080`)
```text
Pod/Host: e5783db29a70  (guestbook-web-1)
Pod/Host: d3e571d5b586  (guestbook-web-2)
Pod/Host: 27c24db15927  (guestbook-web-3)
Pod/Host: e5783db29a70  (guestbook-web-1)
Pod/Host: e5783db29a70  (guestbook-web-1)
```

- **원리 설명**:
  - Nginx가 8080 포트로 들어오는 외부 요청을 수신
  - 도커 내장 DNS(`resolver 127.0.0.11`)를 통해 `web` 서비스에 할당된 3개 컨테이너 IP 주소로 트래픽을 분산 전달
  - 데이터는 단일 Redis 컨테이너 및 볼륨에 안전하게 저장되므로, 어떤 웹 인스턴스가 요청을 처리하더라도 동일한 방명록 데이터를 조회할 수 있음.

---

## 3. `down` 후 `up` vs `down -v` 후 `up` 차이 비교

| 명령어 | 볼륨(Volume) 유지 여부 | 데이터 영속성 | 설명 |
| :--- | :--- | :--- | :--- |
| **`docker compose down`** | **유지됨 (Keep)** | **보존됨** | 컨테이너와 가상 네트워크만 중지 및 삭제하고, 명명된 볼륨(`guestbook_redis-data`)은 유지합니다. 다시 `up` 했을 때 기존 방명록 글이 그대로 유지됩니다. |
| **`docker compose down -v`** | **삭제됨 (Removed)** | **전부 초기화** | `-v` (`--volumes`) 플래그로 인해 컨테이너뿐 아니라 연결된 볼륨까지 호스트 디스크에서 완전히 삭제합니다. 다시 `up` 하면 빈 볼륨이 새로 생성되어 방명록 데이터가 초기화됩니다. |

- **실제 검증 결과**:
  - `down` 후 `up`: 작성된 방명록 글이 삭제되지 않고 남아있음을 확인
  - `down -v` 후 `up`: 볼륨이 함께 파기되어 기존 데이터가 깨끗이 비워진 상태(`DATA_WIPED_CLEAN`)로 새 컨테이너가 시작됨을 확인

---

## 4. `.env` 파일을 Git에 올리지 않는 이유

1. **보안성 (Secret 관리)**:
   - `.env` 파일에는 DB 접속 암호(`REDIS_PASSWORD`), API 키, JWT Secret 등 민감한 인증 정보가 평문으로 저장됩니다.
   - 공개 저장소(GitHub 등)에 업로드 시 전 세계에 비밀번호가 노출되며, 비공개 저장소라도 커밋 기록(Git History)에 남아 유출 위험이 커집니다.
2. **환경별 설정 분리**:
   - 로컬 개발 환경, 테스트(QA) 환경, 운영(Production) 환경마다 사용하는 패스워드나 포트, 도메인 등이 다릅니다.
   - 설정 템플릿 파일인 `.env.example`만 Git에 버전 관리하고, 실제 `.env`는 서버 또는 로컬 개발 장비마다 `.gitignore`로 제외한 뒤 독립적으로 관리하는 것이 표준 실무 원칙(12-Factor App)입니다.
