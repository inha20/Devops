# Week 04 실습: 자동화와 협업 & 네트워크 기초

## 1. 실습 내용 요약
- `for` 반복문과 파이프(`|`), `grep`으로 텍스트 및 파일 다루기
- IP 주소와 포트(Port), TCP/IP 개념 및 로컬 웹 서버 테스트
- 윈도우에서 자꾸 생기는 `Zone.Identifier` 파일 제거 및 `.gitignore` 설정

---

## 2. 셸 자동화와 파이프라인

### (1) 폴더 100개 한 번에 만들기
GUI로 일일이 만들면 한참 걸리는 작업을 반복문 한 줄로 바로 생성함.
```bash
for i in $(seq 1 100); do mkdir -p test/dir$i; done
ls test | wc -l # 100개 생성 확인
```

### (2) 파이프(`|`)와 `grep`
- `|`: 앞 명령어의 출력 결과를 뒤 명령어의 입력으로 바로 넘겨줌.
- `grep`: 원하는 단어가 들어있는 줄만 골라서 보여줌.
```bash
cat diary.txt | grep "DevOps"
```

---

## 3. 네트워크 기본 개념 (IP와 포트)

### (1) IP와 포트 비유
- **IP 주소**: 컴퓨터를 찾아가는 건물 주소 (예: 학교 주소).
- **포트(Port)**: 건물 안에서 몇 호실(어떤 프로그램)인지 구분하는 번호.
- **도커 포트포워딩 (`-p 8080:80`)**: 내 컴퓨터 8080번 문으로 들어온 손님을 컨테이너 내부의 80번 문으로 연결해 주는 것.

### (2) 파이썬 간단 웹 서버 띄우기
```bash
# 8080 포트로 웹 서버 실행
python3 -m http.server 8080 &

# curl 명령어로 응답 헤더 확인
curl -I http://localhost:8080
# HTTP/1.0 200 OK 확인
```

---

## 4. Zone.Identifier 문제 해결
윈도우 환경에서 웹에서 받은 파일에 붙는 메타데이터(`:Zone.Identifier`)가 깃 상태를 지저분하게 만드는 현상이 있었음.

```bash
# 1. 기존에 생긴 Zone.Identifier 파일 전부 찾아서 삭제
find . -type f -name '*:Zone.Identifier' -delete

# 2. 앞으로 깃 추적에 안 잡히게 .gitignore에 추가
echo '*:Zone.Identifier' >> .gitignore
```

---

## 5. 정리
- 파이프(`|`)랑 `grep`을 쓰면 긴 로그 파일에서 원하는 내용만 빠르게 찾을 수 있음.
- IP와 포트 개념을 이해해두니까 나중에 도커 컨테이너 포트 매핑할 때 헷갈리지 않았음.
