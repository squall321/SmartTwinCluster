# Apptainer 바이너리 패키지

이 디렉토리에는 빌드된 Apptainer 바이너리가 포함되어 있습니다.

## 포함된 파일

- `apptainer-binary-1.3.3.tar.gz` - Apptainer 1.3.3 바이너리 및 설정 파일 (27MB)
  - apptainer (실행 파일)
  - apptainer.conf (설정 파일)

## 빌드 정보

- **버전**: 1.3.3
- **빌드 날짜**: 2024년 9월 20일
- **소스**: /home/koopark/apptainer-1.3.3
- **빌드 방법**: `./mconfig && make -C builddir`

## 사용 방법

### 자동 설치 (deploy_apptainers.sh)

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory
./deploy_apptainers.sh
```

이 스크립트가 자동으로:
1. 각 노드에 SSH 접속
2. Apptainer 설치 여부 확인
3. 없으면 이 바이너리를 복사하여 설치
4. Apptainer 이미지도 함께 배포

### 수동 설치

```bash
# 원격 노드에 복사
scp apptainer-binary-1.3.3.tar.gz user@node:/tmp/

# 원격 노드에서 설치
ssh user@node
cd /tmp
tar -xzf apptainer-binary-1.3.3.tar.gz
sudo install -m 755 apptainer /usr/local/bin/
sudo install -m 644 apptainer.conf /usr/local/etc/
apptainer --version
```

## 프로덕션 환경

프로덕션 환경(370개 노드 + viz 10개 노드)에서도 이 바이너리를 사용하여:
- 인터넷 연결 없이 설치 가능
- 일관된 버전 관리
- 빠른 배포 (다운로드 시간 절약)

## 업데이트

새 버전의 Apptainer가 필요한 경우:

1. 새 버전 빌드
2. tar 파일 생성하여 이 디렉토리에 저장
3. deploy_apptainers.sh 업데이트 (버전 번호 변경)

```bash
# 예시
cd /path/to/apptainer-1.4.0/builddir
tar -czf /home/koopark/claude/KooSlurmInstallAutomationRefactory/apptainer/apptainer-binary-1.4.0.tar.gz apptainer apptainer.conf
```
