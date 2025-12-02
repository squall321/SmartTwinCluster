# 🔍 setup_cluster_full.sh 옵션 파일 분석

## 📋 답변: 옵션 파일을 어떻게 받는가?

### ❌ 명령행 인자를 받지 않습니다!

`setup_cluster_full.sh`는 다음과 같이 실행합니다:

```bash
# 인자 없이 실행
./setup_cluster_full.sh

# ❌ 이렇게 하면 안 됨
./setup_cluster_full.sh my_cluster.yaml  # 무시됨!
```

---

## 📁 고정된 파일 이름 사용

### Step 1에서 확인하는 파일

```bash
################################################################################
# Step 1: 설정 파일 확인
################################################################################

if [ -f "my_cluster.yaml" ]; then
    echo "✅ my_cluster.yaml 파일 확인됨"
    # ... 계속 진행
else
    echo "❌ my_cluster.yaml 파일이 없습니다."
    echo "💡 예시 파일을 복사하세요:"
    echo "   cp examples/2node_example.yaml my_cluster.yaml"
    echo "   vim my_cluster.yaml"
    exit 1
fi
```

**고정된 파일 이름: `my_cluster.yaml`**

---

## 🎯 사용 방법

### 1단계: 설정 파일 준비
```bash
cd /home/koopark/claude/KooSlurmInstallAutomation

# 옵션 A: 예시에서 복사
cp examples/2node_example.yaml my_cluster.yaml

# 옵션 B: 다른 이름에서 복사
cp dev_cluster.yaml my_cluster.yaml

# 옵션 C: 직접 생성
vim my_cluster.yaml
```

### 2단계: 설정 파일 편집
```bash
vim my_cluster.yaml

# 최소한 수정할 것:
# - 호스트명
# - IP 주소
# - SSH 사용자
```

### 3단계: 실행
```bash
./setup_cluster_full.sh
# 자동으로 my_cluster.yaml을 읽음
```

---

## 🔄 여러 설정 파일 사용하기

다른 이름의 설정 파일을 사용하려면:

### 방법 1: 심볼릭 링크 (추천)
```bash
# production 설정 사용
ln -sf production_cluster.yaml my_cluster.yaml
./setup_cluster_full.sh

# development 설정으로 변경
ln -sf dev_cluster.yaml my_cluster.yaml
./setup_cluster_full.sh
```

### 방법 2: 복사
```bash
# production 설정 사용
cp production_cluster.yaml my_cluster.yaml
./setup_cluster_full.sh

# development 설정으로 변경
cp dev_cluster.yaml my_cluster.yaml
./setup_cluster_full.sh
```

### 방법 3: 스크립트 수정 (권장하지 않음)
```bash
# setup_cluster_full.sh의 31번째 줄 수정
# 변경 전:
if [ -f "my_cluster.yaml" ]; then

# 변경 후:
CONFIG_FILE="${1:-my_cluster.yaml}"
if [ -f "$CONFIG_FILE" ]; then
```

---

## 📊 다른 스크립트들 비교

### 명령행 인자를 받는 스크립트

#### 1. install_slurm.py ✅
```bash
./install_slurm.py -c my_cluster.yaml
./install_slurm.py -c production.yaml
./install_slurm.py -c dev.yaml
```

#### 2. validate_config.py ✅
```bash
./validate_config.py my_cluster.yaml
./validate_config.py production.yaml
```

#### 3. test_connection.py ✅
```bash
./test_connection.py my_cluster.yaml
```

### 고정 파일 이름을 사용하는 스크립트

#### 1. setup_cluster_full.sh ❌
```bash
# 항상 my_cluster.yaml 사용
./setup_cluster_full.sh
```

#### 2. start_slurm_cluster.sh ❌
```bash
# 설정 파일 자체를 사용하지 않음
# 스크립트 내부에 하드코딩된 IP 사용
./start_slurm_cluster.sh
```

---

## 💡 왜 이렇게 설계되었나?

### setup_cluster_full.sh의 설계 철학

1. **단순성**: 초보자도 쉽게 사용
   ```bash
   # 복잡한 옵션 불필요
   ./setup_cluster_full.sh
   ```

2. **일관성**: 항상 같은 파일 이름
   ```bash
   # 실수로 잘못된 설정 파일 사용 방지
   my_cluster.yaml
   ```

3. **대화형**: 단계별로 확인하며 진행
   ```bash
   read -p "설정 파일을 계속 사용하시겠습니까? (Y/n): "
   read -p "Munge를 자동 설치하시겠습니까? (Y/n): "
   read -p "컨트롤러에 Slurm을 설치하시겠습니까? (Y/n): "
   ```

---

## 🎯 실제 사용 예시

### 시나리오 1: 처음 설치
```bash
cd /home/koopark/claude/KooSlurmInstallAutomation

# 1. 예시 복사
cp examples/2node_example.yaml my_cluster.yaml

# 2. 설정 수정
vim my_cluster.yaml

# 3. 실행
./setup_cluster_full.sh
```

### 시나리오 2: 기존 설정으로 재설치
```bash
cd /home/koopark/claude/KooSlurmInstallAutomation

# my_cluster.yaml이 이미 있으면
./setup_cluster_full.sh
```

### 시나리오 3: 다른 설정으로 설치
```bash
cd /home/koopark/claude/KooSlurmInstallAutomation

# 1. 백업
mv my_cluster.yaml my_cluster.yaml.backup

# 2. 새 설정 복사
cp dev_cluster.yaml my_cluster.yaml

# 3. 실행
./setup_cluster_full.sh

# 4. 원래 설정 복구
mv my_cluster.yaml.backup my_cluster.yaml
```

---

## 📝 요약

### Q: setup_cluster_full.sh는 옵션 파일을 어떻게 받는가?
**A: 받지 않습니다! 항상 `my_cluster.yaml` 파일을 찾습니다.**

### Q: 다른 설정 파일을 사용하려면?
**A: 파일 이름을 `my_cluster.yaml`로 복사하거나 심볼릭 링크를 만드세요.**

```bash
# 방법 1: 복사
cp your_config.yaml my_cluster.yaml

# 방법 2: 심볼릭 링크
ln -sf your_config.yaml my_cluster.yaml
```

### Q: 명령행 인자로 설정 파일을 지정하려면?
**A: `install_slurm.py` 같은 다른 스크립트를 사용하세요:**

```bash
./install_slurm.py -c your_config.yaml
```

---

## 🔗 관련 파일

| 스크립트 | 설정 파일 방식 | 예시 |
|---------|--------------|------|
| `setup_cluster_full.sh` | 고정 (`my_cluster.yaml`) | `./setup_cluster_full.sh` |
| `install_slurm.py` | 명령행 인자 | `./install_slurm.py -c config.yaml` |
| `validate_config.py` | 명령행 인자 | `./validate_config.py config.yaml` |
| `test_connection.py` | 명령행 인자 | `./test_connection.py config.yaml` |
| `start_slurm_cluster.sh` | 사용 안 함 | `./start_slurm_cluster.sh` |

---

작성일: 2025-10-08 18:40 KST
