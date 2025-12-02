# 문제 해결: "ERROR: list index out of range"

## 원인

이 오류는 Python의 `yaml` 모듈이 설치되어 있지 않아서 발생합니다.

## 빠른 해결 방법

### 방법 1: 자동 설치 스크립트 사용 (권장)

```bash
chmod +x install_pyyaml.sh
./install_pyyaml.sh
```

### 방법 2: pip3로 수동 설치

```bash
pip3 install pyyaml
```

또는 sudo 권한이 필요한 경우:

```bash
sudo pip3 install pyyaml
```

### 방법 3: apt-get으로 설치

```bash
sudo apt-get update
sudo apt-get install -y python3-yaml
```

## 설치 확인

설치 후 다음 명령으로 확인:

```bash
python3 -c "import yaml; print(yaml.__version__)"
```

정상적으로 버전이 출력되면 성공입니다.

## 재시도

yaml 모듈 설치 후 다시 동기화 시도:

```bash
./sync_apptainers_to_nodes.sh
```

## 상세 문제 진단

`setup_apptainer_features.sh`를 실행하여 전체 환경을 확인:

```bash
./setup_apptainer_features.sh
```

이 스크립트는:
- Python3 설치 여부
- yaml 모듈 설치 여부  
- SSH, rsync 등 필수 도구
- YAML 파일 구조
- SSH 연결

을 모두 확인합니다.

## 여전히 문제가 있다면

1. **Python3 버전 확인**
   ```bash
   python3 --version
   ```
   Python 3.6 이상이 필요합니다.

2. **pip3 설치 확인**
   ```bash
   pip3 --version
   ```
   없다면:
   ```bash
   sudo apt-get install python3-pip
   ```

3. **가상환경 사용 중이라면**
   ```bash
   source venv/bin/activate
   pip install pyyaml
   ```

4. **권한 문제**
   ```bash
   sudo pip3 install pyyaml
   ```

## 기타 오류

### "compute_nodes가 비어있거나 없습니다"

`my_cluster.yaml` 파일을 확인:

```bash
cat my_cluster.yaml | grep -A20 "compute_nodes:"
```

`compute_nodes` 섹션에 최소 1개 이상의 노드가 정의되어 있어야 합니다.

### "YAML 파싱 오류"

YAML 파일 문법 오류입니다. 들여쓰기를 확인하세요:

```bash
python3 -c "import yaml; yaml.safe_load(open('my_cluster.yaml'))"
```

## 도움말

더 많은 정보는 다음 문서를 참고하세요:

```bash
cat APPTAINER_MANAGEMENT_GUIDE.md
```

또는 도움말 명령:

```bash
./sync_apptainers_to_nodes.sh --help
```
