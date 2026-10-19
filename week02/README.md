# Week 02 실습: 실습 환경 구축 및 Git 기초

## 1. 실습 내용 요약
- WSL2 및 Ubuntu 리눅스 환경 세팅
- 가상화 방식(베어메탈 vs VM vs 컨테이너) 차이점 정리
- 기본 리눅스 명령어(`ls`, `cd`, `mkdir`, `cat`, `rm` 등) 실습
- Git 사용자 설정 및 GitHub CLI(`gh`)로 저장소 연결 후 푸시

---

## 2. 가상화 개념 정리
- **베어메탈**: 물리 PC에 OS 하나 깔고 직접 쓰는 방식. 프로그램끼리 자원 분리가 안 됨.
- **가상머신 (VM)**: 하이퍼바이저 위에 OS를 통째로 여러 개 띄우는 방식. 확실하게 격리되지만 무겁고 느림.
- **컨테이너**: 호스트 OS의 커널을 다 같이 공유하면서 프로세스만 따로 격리해서 띄우는 방식. VM보다 훨씬 가볍고 부팅이 빠름.

---

## 3. Git 설정 및 저장소 생성

### (1) 사용자 정보 등록
```bash
git config --global user.name "inha20"
git config --global user.email "cjh3cjh@naver.com"
```

### (2) 로컬 저장소 생성 후 GitHub 연동
```bash
# 폴더 만들고 git 초기화
mkdir devops && cd devops
git init

# 첫 파일 생성 및 커밋
echo "# DevOps" > README.md
git add README.md
git commit -m "feat: 첫 커밋"

# gh CLI로 GitHub에 public 저장소 만들고 바로 push
gh auth login
gh repo create devops --public --source=. --remote=origin --push
```

---

## 4. 정리
- 컨테이너가 왜 가상머신(VM)보다 효율적인지 개념적으로 이해함.
- GitHub CLI(`gh`)를 쓰면 굳이 웹 브라우저를 열지 않고도 터미널에서 바로 새 레포지토리를 만들고 원격에 올릴 수 있어서 편함.
