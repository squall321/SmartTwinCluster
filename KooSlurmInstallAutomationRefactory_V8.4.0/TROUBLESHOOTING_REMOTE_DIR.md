# 문제 해결: 원격 디렉토리 생성 실패

## 🔴 오류 메시지
```
[ERROR] [node001] 원격 디렉토리 생성 실패
```

## 🔍 원인

1. **/scratch 디렉토리가 없음**
2. **권한 부족** - /scratch에 쓰기 권한이 없음
3. **SSH sudo 권한 문제**
4. **디스크 공간 부족**

## ✅ 해결 방법

### 방법 1: 자동 진단 및 수정 (권장)

```bash
# 1. 권한 부여
chmod +x debug_apptainer_sync.sh
chmod +x create_remote_apptainer_dirs.sh

# 2. 문제 진단
./debug_apptainer_sync.sh

# 3. 자동 디렉토리 생성
./create_remote_apptainer_dirs.sh
```

### 방법 2: 수동으로 각 노드에서 실행

```bash
# node001에 접속
ssh node001

# /scratch 디렉토리 생성 (sudo 필요)
sudo mkdir -p /scratch
sudo chmod 1777 /scratch

# apptainers 디렉토리 생성
mkdir -p /scratch/apptainers
chmod 755 /scratch/apptainers

# 확인
ls -ld /scratch/apptainers

# 종료
exit
```

node002에도 동일하게 반복

### 방법 3: 원격에서 한 번에 실행

```bash
# 모든 노드에 /scratch 생성
for node in node001 node002; do
    echo "==> $node"
    ssh $node 'sudo mkdir -p /scratch && sudo chmod 1777 /scratch'
    ssh $node 'mkdir -p /scratch/apptainers && chmod 755 /scratch/apptainers'
    ssh $node 'ls -ld /scratch/apptainers'
done
```

## 🔧 상세 진단

### 1. SSH 연결 확인

```bash
# 기본 연결 테스트
ssh node001 'echo OK'

# 자세한 디버그
ssh -v node001 'echo OK'
```

**문제 해결:**
- SSH 키가 없다면: `ssh-keygen -t rsa -b 4096`
- 키 복사: `ssh-copy-id node001`

### 2. /scratch 디렉토리 확인

```bash
# 디렉토리 존재 확인
ssh node001 'ls -ld /scratch'

# 없다면 생성
ssh node001 'sudo mkdir -p /scratch && sudo chmod 1777 /scratch'
```

### 3. 권한 확인

```bash
# 현재 권한 확인
ssh node001 'ls -ld /scratch'

# 올바른 권한:
drwxrwxrwt  2 root root 4096 Oct 13 10:00 /scratch
#          ^ sticky bit (1777)
```

### 4. 디스크 공간 확인

```bash
# 디스크 사용량 확인
ssh node001 'df -h /scratch'

# inode 확인
ssh node001 'df -i /scratch'
```

### 5. 수동으로 디렉토리 생성 테스트

```bash
# 테스트 디렉토리 생성
ssh node001 'mkdir -p /scratch/test_dir && echo SUCCESS'

# 성공하면 삭제
ssh node001 'rmdir /scratch/test_dir'
```

## 💡 일반적인 문제들

### 문제 1: "Permission denied"

```bash
# 원인: /scratch에 쓰기 권한이 없음
# 해결:
ssh node001 'sudo chmod 1777 /scratch'
```

### 문제 2: "/scratch: No such file or directory"

```bash
# 원인: /scratch 디렉토리 자체가 없음
# 해결:
ssh node001 'sudo mkdir -p /scratch && sudo chmod 1777 /scratch'
```

### 문제 3: "sudo: a terminal is required"

```bash
# 원인: SSH sudo가 제대로 설정되지 않음
# 해결: /etc/sudoers에 NOPASSWD 추가

# 임시 해결: 각 노드에 직접 로그인
ssh node001
sudo mkdir -p /scratch
sudo chmod 1777 /scratch
mkdir -p /scratch/apptainers
exit
```

### 문제 4: "No space left on device"

```bash
# 원인: 디스크 공간 부족
# 확인:
ssh node001 'df -h'

# 해결: 불필요한 파일 삭제 또는 다른 경로 사용
```

## 🎯 권장 디렉토리 구조

```
/scratch/                       # sticky bit (1777)
└── apptainers/                 # 일반 권한 (755)
    ├── *.def                   # Definition 파일
    └── *.sif                   # Image 파일
```

### /scratch 디렉토리 권한 설명

- `drwxrwxrwt` (1777)
  - 모든 사용자가 읽기/쓰기/실행 가능
  - sticky bit: 파일 소유자만 삭제 가능
  - 임시 디렉토리에 적합

## 🔄 수정된 스크립트 기능

최신 `sync_apptainers_to_nodes.sh`는 다음을 자동으로 처리합니다:

1. ✅ /scratch 존재 여부 확인
2. ✅ 없으면 sudo로 자동 생성
3. ✅ 권한 문제 시 sudo로 재시도
4. ✅ 상세한 오류 메시지 제공

## 📝 확인 체크리스트

설정이 올바른지 확인:

- [ ] SSH passwordless 로그인 가능
- [ ] /scratch 디렉토리 존재
- [ ] /scratch 권한이 1777
- [ ] /scratch/apptainers 생성 가능
- [ ] sudo 권한 있음 (필요 시)
- [ ] 디스크 공간 충분

## 🚀 모든 것이 해결되었다면

```bash
# 동기화 재시도
./sync_apptainers_to_nodes.sh

# 또는 강제 실행
./sync_apptainers_to_nodes.sh --force

# 테스트 모드
./sync_apptainers_to_nodes.sh --dry-run
```

## 📞 추가 도움

여전히 문제가 있다면:

1. `./debug_apptainer_sync.sh` 실행 후 결과 확인
2. 로그 저장: `./debug_apptainer_sync.sh > debug.log 2>&1`
3. 이슈 등록 시 debug.log 첨부

## 🔗 관련 문서

- `APPTAINER_MANAGEMENT_GUIDE.md` - 전체 가이드
- `TROUBLESHOOTING_PYYAML.md` - PyYAML 설치 문제
- `SSH_PASSWORDLESS_README.md` - SSH 설정 가이드
