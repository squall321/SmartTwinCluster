# 🔧 sinfo, sbatch 명령어가 안 될 때 해결법

## 🎯 문제 상황

`setup_cluster_full.sh`를 실행했는데도 명령어가 작동하지 않음:

```bash
$ sinfo
-bash: sinfo: command not found

$ sbatch test.sh
-bash: sbatch: command not found
```

---

## ⚡ 빠른 해결 (1분)

### 방법 1: 자동 수정 스크립트 실행 ⭐ 추천

```bash
cd /home/koopark/claude/KooSlurmInstallAutomation
chmod +x fix_slurm_path.sh
./fix_slurm_path.sh
```

**이 스크립트가 자동으로:**
- ✅ `/etc/profile.d/slurm.sh` 확인/생성
- ✅ 현재 터미널에 PATH 적용
- ✅ 명령어 작동 확인
- ✅ ~/.bashrc 업데이트 (선택)

---

### 방법 2: 수동으로 PATH 설정 (30초)

#### 옵션 A: 기존 파일 로드
```bash
source /etc/profile.d/slurm.sh
```

#### 옵션 B: 직접 PATH 추가
```bash
export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH
```

#### 확인
```bash
which sinfo
sinfo --version
```

---

### 방법 3: 새 터미널 열기 (가장 간단)

`/etc/profile.d/slurm.sh` 파일이 있으면 **새 터미널에서 자동 로드**됩니다:

1. 현재 터미널 닫기
2. 새 터미널 열기
3. `sinfo` 입력

---

### 방법 4: 절대 경로로 실행 (임시)

PATH 설정 없이 바로 사용:

```bash
/usr/local/slurm/bin/sinfo
/usr/local/slurm/bin/squeue
/usr/local/slurm/bin/sbatch test.sh
```

---

## 🔍 진단 스크립트

자세한 문제 확인:

```bash
cd /home/koopark/claude/KooSlurmInstallAutomation
chmod +x diagnose_slurm_path.sh
./diagnose_slurm_path.sh
```

**확인 항목:**
1. ✅ Slurm 바이너리 파일 존재 여부
2. ✅ `/etc/profile.d/slurm.sh` 파일 확인
3. ✅ 현재 PATH 설정 확인
4. ✅ 명령어 실행 테스트
5. ✅ 해결 방법 제시

---

## 💡 왜 이런 일이 발생하나?

### 원인 1: PATH가 로드되지 않음

`/etc/profile.d/slurm.sh`는:
- ✅ 새 **로그인 셸**에서 자동 로드됨
- ❌ 이미 열린 터미널에는 적용 안 됨

**해결:**
```bash
source /etc/profile.d/slurm.sh
```

---

### 원인 2: 파일이 생성되지 않음

`setup_cluster_full.sh`에서 `install_slurm_cgroup_v2.sh`가 실패했을 수 있음

**확인:**
```bash
ls -la /etc/profile.d/slurm.sh
cat /etc/profile.d/slurm.sh
```

**없으면 생성:**
```bash
sudo tee /etc/profile.d/slurm.sh > /dev/null << 'EOF'
# Slurm Environment
export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH
export LD_LIBRARY_PATH=/usr/local/slurm/lib:$LD_LIBRARY_PATH
export MANPATH=/usr/local/slurm/share/man:$MANPATH
EOF

sudo chmod 644 /etc/profile.d/slurm.sh
```

---

### 원인 3: non-login shell 사용

일부 터미널은 **non-login shell**로 시작되어 `/etc/profile.d/`를 로드하지 않음

**해결: ~/.bashrc에 추가**
```bash
echo 'source /etc/profile.d/slurm.sh 2>/dev/null || export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

---

## ✅ 영구 해결 방법

### 1단계: 자동 수정 스크립트 실행
```bash
cd /home/koopark/claude/KooSlurmInstallAutomation
./fix_slurm_path.sh
```

### 2단계: ~/.bashrc 업데이트 (권장)
```bash
echo 'source /etc/profile.d/slurm.sh 2>/dev/null || export PATH=/usr/local/slurm/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

### 3단계: 확인
```bash
# 새 터미널 열고
which sinfo
sinfo --version
```

---

## 📊 다른 사용자도 같은 문제?

### 모든 사용자에게 적용

`/etc/profile.d/slurm.sh`는 **모든 사용자**에게 적용됩니다.

각 사용자가 새 터미널을 열면 자동으로 로드됩니다.

### 특정 사용자만 문제

해당 사용자의 `~/.bashrc` 또는 `~/.bash_profile` 확인:

```bash
# 문제가 있는 사용자로 로그인
echo $PATH | grep slurm

# 없으면 추가
echo 'export PATH=/usr/local/slurm/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

---

## 🔗 관련 스크립트

| 스크립트 | 용도 | 실행 |
|---------|------|------|
| `fix_slurm_path.sh` | 자동 수정 ⭐ | `./fix_slurm_path.sh` |
| `diagnose_slurm_path.sh` | 상세 진단 | `./diagnose_slurm_path.sh` |
| `verify_slurm_commands.sh` | 명령어 확인 | `./verify_slurm_commands.sh` |

---

## 🎯 요약

### 가장 빠른 해결책 (10초)

```bash
source /etc/profile.d/slurm.sh
sinfo
```

### 영구 해결책 (1분)

```bash
./fix_slurm_path.sh
# Y를 눌러 ~/.bashrc 업데이트
```

### 확인

```bash
which sinfo
sinfo --version
sinfo
```

---

## 🆘 그래도 안 되면?

1. **Slurm 설치 확인**
   ```bash
   ls -la /usr/local/slurm/bin/
   /usr/local/slurm/bin/sinfo --version
   ```

2. **재설치**
   ```bash
   cd /home/koopark/claude/KooSlurmInstallAutomation
   sudo bash install_slurm_cgroup_v2.sh
   ```

3. **상세 진단**
   ```bash
   ./diagnose_slurm_path.sh
   ```

---

작성일: 2025-10-08 18:50 KST
