# Week 05 실습: 도커 기초 및 Nginx 다중 컨테이너 실행

## 1. 실습 내용 요약
- Docker 기본 명령어(`run`, `ps`, `logs`, `exec`, `stop`, `rm`) 익히기
- Nginx 웹 컨테이너를 포트포워딩(`8080:80`)으로 실행하고 접속 테스트
- GitHub Issue 기반으로 브랜치 만들고 PR 올려서 머지하는 협업 흐름 실습
- 포트가 다른 3개의 Nginx 컨테이너를 띄우고 내부 `index.html` 수정해보기 (혼자서 해보기)

---

## 2. Docker 환경 확인 및 Nginx 실행

### (1) 도커 동작 테스트
```bash
$ docker --version
$ docker run --rm hello-world
# Hello from Docker! 출력 확인
```

### (2) web 이름으로 nginx 실행 및 응답 확인
```bash
# 백그라운드(-d)로 8080 포트 연결해서 실행
$ docker run -d -p 8080:80 --name web nginx

# curl로 200 OK 응답 확인
$ curl -I http://localhost:8080
HTTP/1.1 200 OK
```

---

## 3. GitHub Issue 기반 실습 관리
- **이슈 생성**: `5주차: 도커 기초 실습` (#1) 이슈 등록
- **작업 브랜치**: `git switch -c docs/issue-1-docker-start`
- **PR 및 이슈 닫기**: PR 본문에 `Close #1`을 적어서 PR 머지 시 이슈가 자동으로 `CLOSED` 되도록 연결함.

---

## 4. [혼자서 해보기] 포트별 Nginx 3개 띄우고 index.html 수정하기

### (1) 3개 컨테이너 각각 다른 포트로 실행
```bash
docker run -d -p 8091:80 --name nginx1 nginx
docker run -d -p 8092:80 --name nginx2 nginx
docker run -d -p 8093:80 --name nginx3 nginx
```

### (2) 컨테이너 안으로 들어가서 index.html 내용 바꾸기 (`docker exec`)
```bash
docker exec nginx1 sh -c 'echo "<h1>Hi</h1>" > /usr/share/nginx/html/index.html'
docker exec nginx2 sh -c 'echo "<h1>Hello</h1>" > /usr/share/nginx/html/index.html'
docker exec nginx3 sh -c 'echo "<h1>Bonjour</h1>" > /usr/share/nginx/html/index.html'
```

### (3) curl 접속 테스트
```bash
$ curl http://localhost:8091
<h1>Hi</h1>

$ curl http://localhost:8092
<h1>Hello</h1>

$ curl http://localhost:8093
<h1>Bonjour</h1>
```

### (4) 컨테이너 상태 확인 및 화면 캡처
```text
$ docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
NAMES     STATUS          PORTS
nginx1    Up 10 minutes   0.0.0.0:8091->80/tcp
nginx2    Up 10 minutes   0.0.0.0:8092->80/tcp
nginx3    Up 10 minutes   0.0.0.0:8093->80/tcp
web       Up 15 minutes   0.0.0.0:8080->80/tcp
```
- 브라우저에서 `localhost:8091`, `8092`, `8093` 접속했을 때 `Hi`, `Hello`, `Bonjour`가 각각 다르게 뜨는 것을 확인하고 캡처함.
- 캡처 파일: 저장소 `images/스크린샷 2026-09-30 121040.png`

---

## 5. 실습 끝난 컨테이너 정리
```bash
docker rm -f web nginx1 nginx2 nginx3
```

---

## 6. 정리
- 똑같은 Nginx 이미지라도 포트만 다르게 연결해 주면 독립된 웹 서버 여러 대를 내 컴퓨터 한 대에서 동시에 띄울 수 있다는 점을 확인했음.
- `docker exec`를 쓰면 굳이 컨테이너를 새로 빌드하지 않고도 내부 파일이나 설정을 바로 수정해 볼 수 있어서 유용함.
