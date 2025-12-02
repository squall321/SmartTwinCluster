# SSH 비밀번호 없이 Slurm 설치하기

## 🎯 문제

`setup_cluster_full.sh` 실행 시 각 노드마다 비밀번호를 입력해야 해서 번거로움

## ✅ 해결

**SSH 키 기반 인증** 설정 → **한 번만 설정**하면 이후 비밀번호 입력 불필요!

---

## ⚡ 3단계 빠른 설정

### Step 1: SSH 키 생성

```bash
ssh-keygen -t rsa -b 4096
```

질문이 나오면 모두 **Enter** (비밀번호 없이)

### Step 2: 각 노드에 공개키 복사

```bash
ssh-copy-id koopark@192.168.122.90   # node001
ssh-copy-id koopark@192.168.122.103  # node002
```

각 노드의 비밀번호를 **딱 한 번씩만** 입력

### Step 3: 테스트

```bash
ssh node001 'hostname'  # 비밀번호 없이 접속 확인
```

---

## 🚀 자동 설정 스크립트

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory

# 자동 설정
chmod +x setup_ssh_passwordless.sh
./setup_ssh_passwordless.sh

# 또는 가이드 보기
./QUICK_SSH_PASSWORDLESS.sh
```

---

## ✨ 효과

### ✅ 비밀번호 없이 작동

```bash
./setup_cluster_full.sh  # ← 비밀번호 입력 없음!
ssh node001
scp file.txt node001:/tmp/
```

---

## 📚 상세 가이드

**아티팩트**에서 전체 가이드를 확인하세요:
- SSH 키 인증 원리
- 트러블슈팅
- 보안 고려사항
- 체크리스트

---

**위치**: `/home/koopark/claude/KooSlurmInstallAutomationRefactory/`
