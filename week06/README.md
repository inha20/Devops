# Week 06 실습 보고서: 도커파일(Dockerfile) 및 배포

## 1. 내 이미지 주소
- **v1 이미지**: `ghcr.io/inha20/guestbook:v1`
- **v2 이미지**: `ghcr.io/inha20/guestbook:v2`

---

## 2. 친구(또는 제공된) 이미지를 실행한 결과
- 실행 명령어:
  ```bash
  docker run -d -p 9090:5000 --name friend ghcr.io/makyraen/inhatc-devops-guestbook:v1
  ```
- 결과: 브라우저(`http://localhost:9090`) 접속 시 정상적으로 방명록 웹 애플리케이션이 구동되었으며, 새 글 등록이 원활하게 작동함을 확인.

---

## 3. Dockerfile의 각 줄이 하는 일 설명

```dockerfile
# 1. Python 3.12의 경량화(slim) 버전을 기본 베이스 이미지로 지정
FROM python:3.12-slim

# 2. 컨테이너 내부의 작업 디렉터리를 /app으로 설정 (없으면 자동 생성)
WORKDIR /app

# 3. 호스트의 requirements.txt 파일만 먼저 이미지의 /app 디렉터리로 복사
COPY requirements.txt .

# 4. pip 캐시를 남기지 않고 필요한 라이브러리(Flask, redis 등)들을 설치
RUN pip install --no-cache-dir -r requirements.txt

# 5. 소스 코드와 템플릿 등 현재 디렉터리의 나머지 파일들을 이미지로 복사
COPY . .

# 6. 보안을 위해 root가 아닌 일반 사용자(appuser)를 생성
RUN useradd -m appuser

# 7. 이후 컨테이너 실행 권한을 생성된 appuser로 전환
USER appuser

# 8. 애플리케이션에서 참조할 기본 환경 변수(제목, 테마 색상) 정의
ENV APP_TITLE="최종훈의 방명록 V2" \
    THEME_COLOR="#8A2BE2"

# 9. 컨테이너가 5000번 포트를 사용할 예정임을 명시 (문서화 용도)
EXPOSE 5000

# 10. 컨테이너가 시작될 때 파이썬으로 app.py를 실행
CMD ["python", "app.py"]
```

---

## 4. 빌드 캐시가 동작한 로그 (CACHED)

코드 변경 시 상대적으로 변경이 드문 라이브러리 설치 단계(`requirements.txt`, `pip install`)는 캐시를 재사용하여 빌드 속도를 크게 향상시킴.

```text
=> CACHED [3/6] COPY requirements.txt .
=> CACHED [4/6] RUN pip install --no-cache-dir -r requirements.txt
=> [5/6] COPY . .
=> [6/6] RUN useradd -m appuser
```

- **설명**: 코드가 한 줄 바뀌더라도 변경이 적은 패키지 설치 단계를 앞에 배치하면, 무거운 `pip install`을 매번 다시 하지 않고 `CACHED`로 건너뛰어 빌드 시간이 대폭 단축됩니다.

---

## 5. 설정을 넣는 세 가지 방법(코드 / ENV / -e)의 차이 요약

| 방법 | 언제 확정되는가 | 설정을 바꾸기 위해 필요한 작업 |
| :--- | :--- | :--- |
| **app.py 기본값 수정** | 코드 작성 시점 | 소스 코드 수정 후 도커 이미지 재빌드 |
| **Dockerfile의 ENV** | 이미지 빌드 시점 | Dockerfile 수정 후 도커 이미지 재빌드 |
| **docker run -e** | 컨테이너 실행 시점 | 재빌드 없이 컨테이너만 새 옵션으로 재실행 |

- **우선순위**:
  `코드 기본값 (app.py)` **<** `Dockerfile의 ENV (이미지 기본값)` **<** `docker run -e (실행 시 주입)`
- 실행 시 주입한 `-e` 설정이 가장 높은 우선순위로 다른 모든 기본값을 덮어씁니다.
