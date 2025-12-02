# 🔐 Munge 수동 설치 가이드

Munge가 자동으로 설치되지 않았을 경우 수동으로 설치하는 방법입니다.

## 🚀 빠른 설치 (스크립트 사용)

### 1. 컨트롤러 (smarttwincluster)

```bash
cd ~/claude/KooSlurmInstallAutomation
chmod +x install_munge_manual.sh
sudo ./install_munge_manual.sh controller
```

### 2. 계산 노드들 (node1, node2)

```bash
# 각 노드에서
cd ~/claude/KooSlurmInstallAutomation
chmod +x install_munge_manual.sh
sudo ./install_munge_manual.sh
```

### 3. 키 복사

```bash
# 컨트롤러에서
sudo scp /etc/munge/munge.key koopark@192.168.122.90:/tmp/
sudo scp /etc/munge/munge.key koopark@192.168.122.103:/tmp/

# 각 계산 노드에서
ssh 192.168.122.90
sudo mv /tmp/munge.key /etc/munge/
sudo chown munge:munge /etc/munge/munge.key
sudo chmod 400 /etc/munge/munge.key
sudo systemctl restart munge

ssh 192.168.122.103
sudo mv /tmp/munge.key /etc/munge/
sudo chown munge:munge /etc/munge/munge.key
sudo chmod 400 /etc/munge/munge.key
sudo systemctl restart munge
```

## 📋 수동 설치 (단계별)

### Step 1: Munge 설치

#### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install -y munge libmunge2 libmunge-dev
```

#### CentOS/RHEL
```bash
sudo yum install -y munge munge-libs munge-devel
```

### Step 2: 디렉토리 설정

```bash
sudo mkdir -p /etc/munge /var/log/munge /var/lib/munge /run/munge
sudo chown -R munge:munge /etc/munge /var/log/munge /var/lib/munge /run/munge
sudo chmod 700 /etc/munge /var/lib/munge /run/munge
sudo chmod 755 /var/log/munge
```

### Step 3: Munge 키 생성 (컨트롤러에서만)

```bash
# 방법 1
sudo create-munge-key -f

# 방법 2 (방법 1이 안 되면)
sudo /usr/sbin/create-munge-key -f

# 방법 3 (둘 다 안 되면)
sudo dd if=/dev/urandom bs=1 count=1024 of=/etc/munge/munge.key

# 권한 설정
sudo chown munge:munge /etc/munge/munge.key
sudo chmod 400 /etc/munge/munge.key
```

### Step 4: Munge 키 배포 (컨트롤러 → 계산 노드)

```bash
# 컨트롤러에서
sudo scp /etc/munge/munge.key koopark@192.168.122.90:/tmp/
sudo scp /etc/munge/munge.key koopark@192.168.122.103:/tmp/

# node1에서
sudo mv /tmp/munge.key /etc/munge/
sudo chown munge:munge /etc/munge/munge.key
sudo chmod 400 /etc/munge/munge.key

# node2에서
sudo mv /tmp/munge.key /etc/munge/
sudo chown munge:munge /etc/munge/munge.key
sudo chmod 400 /etc/munge/munge.key
```

### Step 5: Munge 서비스 시작 (모든 노드)

```bash
sudo systemctl enable munge
sudo systemctl restart munge
sudo systemctl status munge
```

### Step 6: 테스트

```bash
# 각 노드에서
munge -n | unmunge

# 또는
/usr/bin/munge -n | /usr/bin/unmunge

# 성공하면 다음과 같은 출력:
# STATUS:           Success (0)
# ENCODE_HOST:      hostname
# ...
```

### Step 7: 노드 간 인증 테스트

```bash
# 컨트롤러에서
munge -n | ssh 192.168.122.90 unmunge
munge -n | ssh 192.168.122.103 unmunge

# 성공하면 "Success" 메시지 출력
```

## ✅ 검증

모든 노드에서:

```bash
# 서비스 상태
sudo systemctl is-active munge

# 인증 테스트
munge -n | unmunge | grep SUCCESS
```

## 🐛 문제 해결

### munge: command not found

```bash
# PATH 확인
which munge

# 없으면 절대 경로 사용
/usr/bin/munge -n | /usr/bin/unmunge
```

### 권한 오류

```bash
sudo chown -R munge:munge /etc/munge /var/lib/munge /var/log/munge /run/munge
sudo chmod 700 /etc/munge
sudo chmod 400 /etc/munge/munge.key
```

### 서비스 시작 실패

```bash
# 로그 확인
sudo journalctl -u munge -n 50

# 수동 시작 시도
sudo munged -f

# 디렉토리 재생성
sudo rm -rf /run/munge
sudo mkdir -p /run/munge
sudo chown munge:munge /run/munge
sudo chmod 700 /run/munge
sudo systemctl restart munge
```

## 💡 완료 후

Munge 설치가 완료되면:

```bash
cd ~/claude/KooSlurmInstallAutomation
source venv/bin/activate
./setup_cluster_full.sh
```

계속 진행하면 됩니다!
