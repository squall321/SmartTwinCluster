# 🔐 Munge 자동 설치 스크립트 사용법

## ✨ 새로운 기능: 비밀번호 캐싱

이제 비밀번호를 **한 번만** 입력하면 모든 노드에 자동으로 적용됩니다!

## 🚀 사용 방법

### 방법 1: setup_cluster_full.sh에서 자동 실행

```bash
cd ~/claude/KooSlurmInstallAutomation
source venv/bin/activate
./setup_cluster_full.sh
```

Step 5에서 `Y` 입력하면 자동으로 실행됩니다.

### 방법 2: 독립 실행

```bash
chmod +x install_munge_auto.sh
./install_munge_auto.sh
```

## 💡 주요 기능

### 1. 비밀번호 한 번만 입력
```
📝 비밀번호 입력
================================
노드들의 비밀번호를 입력하세요.
(모든 노드의 비밀번호가 같다고 가정합니다)

비밀번호: ********
비밀번호 확인: ********
```

### 2. 자동 재시도
만약 어떤 노드의 비밀번호가 다르면:
```
❌ SSH 연결 실패 - 비밀번호가 틀렸을 수 있습니다.

🔑 node1의 비밀번호를 다시 입력하세요:
비밀번호: ********
```

### 3. 자동 검증
설치 후 자동으로 검증:
- 각 노드에서 Munge 서비스 상태 확인
- 노드 간 인증 테스트
- 상세한 결과 보고

## 📋 실행 과정

```
===============================================================================
🔐 Munge 자동 설치 (비밀번호 캐싱)
===============================================================================

1단계: 컨트롤러 Munge 설치
  ✅ Munge 서비스 실행 중
  ✅ Munge 테스트 성공!

2단계: 계산 노드 Munge 설치
  📌 node1 (192.168.122.90)
    [1/5] SSH 연결 테스트... ✅
    [2/5] 설치 스크립트 복사... ✅
    [3/5] Munge 설치 중... ✅
    [4/5] Munge 키 복사... ✅
    [5/5] 서비스 시작... ✅

  📌 node2 (192.168.122.103)
    [1/5] SSH 연결 테스트... ✅
    [2/5] 설치 스크립트 복사... ✅
    [3/5] Munge 설치 중... ✅
    [4/5] Munge 키 복사... ✅
    [5/5] 서비스 시작... ✅

3단계: Munge 검증
  📌 컨트롤러: ✅ 정상
  📌 node1: ✅ 정상
  📌 node2: ✅ 정상

4단계: 노드 간 인증 테스트
  📌 컨트롤러 → node1: ✅ 인증 성공
  📌 컨트롤러 → node2: ✅ 인증 성공

🎉 Munge 설치 및 검증 완료!
```

## 🔧 기술적 특징

### 비밀번호 캐싱
- `sshpass`를 사용하여 비밀번호 자동 입력
- 메모리에만 저장, 파일로 저장하지 않음
- 노드별로 다른 비밀번호 지원

### 에러 처리
- 연결 실패시 해당 노드만 건너뛰기
- 비밀번호 틀릴 경우 재입력 기회 제공
- 상세한 에러 메시지 제공

### 보안
- 비밀번호는 화면에 표시되지 않음 (`-s` 옵션)
- 비밀번호 확인 단계 포함
- SSH 키 기반 인증으로 전환 권장

## 🆚 기존 방식 vs 새로운 방식

### 기존 방식 (install_munge_manual.sh)
```bash
# 각 노드마다 수동으로 실행
ssh node1
sudo ./install_munge_manual.sh
exit

ssh node2
sudo ./install_munge_manual.sh
exit

# 키 복사도 수동으로
sudo scp /etc/munge/munge.key node1:/tmp/
ssh node1
sudo mv /tmp/munge.key /etc/munge/
...
```

### 새로운 방식 (install_munge_auto.sh)
```bash
# 비밀번호 한 번만 입력
./install_munge_auto.sh
# 입력: 비밀번호
# → 모든 노드 자동 설치 완료!
```

## 🐛 문제 해결

### sshpass가 없는 경우
```bash
sudo apt install sshpass  # Ubuntu
sudo yum install sshpass  # CentOS
```

스크립트가 자동으로 설치 시도합니다.

### 비밀번호가 계속 틀리는 경우
1. 각 노드의 비밀번호 확인
2. SSH 키 기반 인증 설정 권장:
   ```bash
   ssh-keygen -t rsa -b 4096
   ssh-copy-id koopark@192.168.122.90
   ssh-copy-id koopark@192.168.122.103
   ```

### 일부 노드만 실패하는 경우
실패한 노드만 수동으로 설치:
```bash
ssh 192.168.122.90
sudo ./install_munge_manual.sh
```

## 💡 권장 사항

1. **SSH 키 기반 인증 설정** (비밀번호 입력 불필요)
2. **모든 노드 동일한 비밀번호** (간편한 관리)
3. **sshpass 사전 설치** (자동화 향상)

## 📚 관련 문서

- 수동 설치 가이드: `MUNGE_INSTALL_GUIDE.md`
- 수동 스크립트: `install_munge_manual.sh`
- 전체 설정: `setup_cluster_full.sh`

---

이제 Munge 설치가 훨씬 편리해졌습니다! 🎉
