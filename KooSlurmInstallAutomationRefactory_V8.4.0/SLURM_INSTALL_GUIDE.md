# 📘 Slurm 완전 설치 가이드

현재 상태: Munge, NFS, slurm.conf는 준비 완료 ✅  
필요한 것: **Slurm 바이너리 설치** 📦

---

## 🚀 빠른 설치 (자동 스크립트)

```bash
cd ~/claude/KooSlurmInstallAutomation
chmod +x install_slurm_binary.sh
./install_slurm_binary.sh
```

---

## 📋 수동 설치 (모든 노드에서)

### 1️⃣ Slurm 다운로드 및 압축 해제

```bash
cd ~
wget https://download.schedmd.com/slurm/slurm-23.02.7.tar.bz2
tar -xjf slurm-23.02.7.tar.bz2
cd slurm-23.02.7
```

### 2️⃣ 컴파일 및 설치

```bash
./configure \
    --prefix=/usr/local/slurm \
    --sysconfdir=/usr/local/slurm/etc \
    --with-munge=/usr \
    --enable-pam

make -j$(nproc)
sudo make install
```

**주의:** 모든 노드에서 동일하게 실행해야 합니다!
- 컨트롤러: `smarttwincluster`
- 계산 노드: `192.168.122.90`, `192.168.122.103`

### 3️⃣ Slurm 사용자 생성

```bash
sudo useradd -r -u 64030 -s /bin/false slurm
```

### 4️⃣ 필수 디렉토리 생성 및 권한 설정

```bash
# 모든 노드에서
sudo mkdir -p /var/spool/slurm/state
sudo mkdir -p /var/spool/slurm/d
sudo mkdir -p /var/log/slurm
sudo chown -R slurm:slurm /var/spool/slurm /var/log/slurm
sudo chmod 755 /var/spool/slurm /var/log/slurm
```

### 5️⃣ slurm.conf 확인

```bash
# 이미 생성되어 있어야 함
ls -la /usr/local/slurm/etc/slurm.conf
```

없으면:
```bash
cat /usr/local/slurm/etc/slurm.conf
```

### 6️⃣ systemd 서비스 파일 생성

#### 컨트롤러 (smarttwincluster)

```bash
sudo tee /etc/systemd/system/slurmctld.service > /dev/null <<'EOF'
[Unit]
Description=Slurm controller daemon
After=network.target munge.service
Requires=munge.service

[Service]
Type=forking
EnvironmentFile=-/etc/default/slurmctld
ExecStart=/usr/local/slurm/sbin/slurmctld $SLURMCTLD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/var/run/slurmctld.pid
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes

[Install]
WantedBy=multi-user.target
EOF
```

#### 계산 노드 (192.168.122.90, 192.168.122.103)

```bash
sudo tee /etc/systemd/system/slurmd.service > /dev/null <<'EOF'
[Unit]
Description=Slurm node daemon
After=network.target munge.service
Requires=munge.service

[Service]
Type=forking
EnvironmentFile=-/etc/default/slurmd
ExecStart=/usr/local/slurm/sbin/slurmd $SLURMD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/var/run/slurmd.pid
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes

[Install]
WantedBy=multi-user.target
EOF
```

### 7️⃣ systemd 리로드

```bash
sudo systemctl daemon-reload
```

### 8️⃣ 서비스 활성화 및 시작

#### 컨트롤러
```bash
sudo systemctl enable slurmctld
sudo systemctl start slurmctld
sudo systemctl status slurmctld
```

#### 계산 노드
```bash
sudo systemctl enable slurmd
sudo systemctl start slurmd
sudo systemctl status slurmd
```

---

## ✅ 설치 확인

### 1. 서비스 상태 확인

```bash
# 컨트롤러
sudo systemctl status slurmctld

# 계산 노드
sudo systemctl status slurmd
```

### 2. 노드 상태 확인

```bash
/usr/local/slurm/bin/sinfo
/usr/local/slurm/bin/sinfo -N
```

**정상 출력:**
```
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
main*        up   infinite      2   idle node[001-002]
```

### 3. 노드 상세 정보

```bash
/usr/local/slurm/bin/scontrol show nodes
```

---

## 🐛 문제 해결

### 문제 1: "Unit slurmctld.service not found"

**원인:** 서비스 파일이 없음

**해결:**
```bash
# 서비스 파일 생성 (위 6️⃣ 참조)
sudo systemctl daemon-reload
sudo systemctl start slurmctld
```

### 문제 2: "slurmctld: error: This host (smarttwincluster) is not a valid controller"

**원인:** slurm.conf의 호스트명이 틀림

**해결:**
```bash
# 현재 호스트명 확인
hostname

# slurm.conf 수정
sudo vi /usr/local/slurm/etc/slurm.conf
# SlurmctldHost=<실제 호스트명>

# 서비스 재시작
sudo systemctl restart slurmctld
```

### 문제 3: 노드가 "down" 상태

```bash
# 노드 상태 확인
/usr/local/slurm/bin/sinfo -N

# 노드 활성화
/usr/local/slurm/bin/scontrol update NodeName=node001 State=RESUME
/usr/local/slurm/bin/scontrol update NodeName=node002 State=RESUME
```

### 문제 4: Munge 인증 실패

```bash
# Munge 상태 확인
sudo systemctl status munge

# Munge 재시작
sudo systemctl restart munge

# Slurm 재시작
sudo systemctl restart slurmctld  # 컨트롤러
sudo systemctl restart slurmd     # 계산 노드
```

### 문제 5: 로그 확인

```bash
# 컨트롤러 로그
sudo tail -f /var/log/slurm/slurmctld.log

# 계산 노드 로그
sudo tail -f /var/log/slurm/slurmd.log
```

---

## 📚 PATH 설정

편의를 위해 PATH에 추가:

```bash
# ~/.bashrc에 추가
echo 'export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH' >> ~/.bashrc
source ~/.bashrc

# 이제 간단하게 사용 가능
sinfo
squeue
sbatch
```

---

## 🧪 테스트 Job 제출

### 간단한 테스트

```bash
cat > test_job.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=test
#SBATCH --output=test_%j.out
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=00:01:00

echo "Hello from $(hostname)"
sleep 10
echo "Test complete"
EOF

sbatch test_job.sh
squeue
```

---

## 📊 다음 단계

Slurm 설치 완료 후:

1. **MPI 설치**
   ```bash
   python3 install_mpi.py
   ```

2. **Apptainer 이미지 동기화**
   ```bash
   python3 sync_apptainer_images.py
   ```

3. **MPI + Apptainer Job 제출**
   ```bash
   sbatch job_templates/submit_mpi_apptainer.sh myapp.sif /usr/bin/myprogram
   ```

---

## 🔗 관련 문서

- Slurm 공식 문서: https://slurm.schedmd.com/
- Quick Start: https://slurm.schedmd.com/quickstart.html
- Configuration: https://slurm.schedmd.com/slurm.conf.html

---

**💡 팁:** 자동 설치 스크립트를 사용하면 위 과정을 한 번에 처리할 수 있습니다:
```bash
./install_slurm_binary.sh
```
