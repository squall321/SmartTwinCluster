# Apptainer 디렉토리 구조 재편성 완료 보고서

## 📋 개요

날짜: 2025-10-21
작업자: Claude Code
목적: Apptainer 이미지 및 작업 디렉토리 구조를 FHS 표준에 맞게 재편성

## 🎯 변경 사항 요약

### 이전 구조 (Before)
```
/scratch/apptainers/
├── vnc_desktop.sif        # 이미지 (쓰기 가능 위치에 보관)
├── vnc_gnome.sif
└── sessions/              # 세션 데이터

/scratch/vnc_sandboxes/    # 샌드박스
/tmp/vnc_logs/             # 로그 (재부팅 시 삭제됨)
```

### 새로운 구조 (After)
```
프로젝트/apptainer/
├── compute-node-images/   # 계산 노드용 이미지 원본
└── viz-node-images/       # VNC 노드용 이미지 원본
    ├── vnc_desktop.sif
    └── vnc_gnome.sif

각 노드:
├── /opt/apptainers/       # 읽기 전용 이미지 (root 소유)
│   ├── vnc_desktop.sif
│   └── vnc_gnome.sif
└── /scratch/
    ├── vnc_sandboxes/     # 쓰기 가능 샌드박스
    ├── vnc_sessions/      # 세션 데이터
    └── vnc_logs/          # 로그 (영구 보존)
```

## 📁 상세 변경 내역

### 1. 프로젝트 디렉토리 구조
```bash
apptainer/
├── apptainer-binary-1.3.3.tar.gz    # Apptainer 실행 파일
├── compute-node-images/              # 계산 노드용 (현재 비어있음)
└── viz-node-images/                  # VNC/시각화 노드용
    ├── vnc_desktop.sif (511MB)       # XFCE4 Desktop
    └── vnc_gnome.sif (841MB)         # GNOME Desktop
```

### 2. 배포 스크립트 수정

**파일**: [deploy_apptainers.sh](deploy_apptainers.sh)

**주요 변경**:
- 원본 경로: `PROJECT_APPTAINER_DIR="$SCRIPT_DIR/apptainer"`
- 배포 대상: `/opt/apptainers` (root 소유, 읽기 전용)
- 작업 디렉토리: `/scratch/{vnc_sandboxes,vnc_sessions,vnc_logs}`
- 노드 타입별 이미지 자동 선택 및 배포
- Controller도 동일한 구조로 로컬 배포

**새로운 기능**:
- `/opt/apptainers`에 sudo로 이미지 복사 (root 소유)
- `/scratch` 작업 디렉토리 자동 생성 및 권한 설정
- 모든 `.sif` 파일 자동 감지 및 배포

### 3. VNC API 경로 업데이트

**파일**: [dashboard/backend_5010/vnc_api.py](dashboard/backend_5010/vnc_api.py:45-49)

**변경된 경로**:
```python
VNC_IMAGES_DIR = "/opt/apptainers"           # 읽기 전용 이미지 저장소
VNC_SANDBOXES_DIR = "/scratch/vnc_sandboxes" # 쓰기 가능 샌드박스
VNC_SESSIONS_DIR = "/scratch/vnc_sessions"   # 세션 데이터
VNC_LOG_DIR = "/scratch/vnc_logs"            # 로그 (재부팅 후에도 유지)
```

## ✅ 배포 결과

### Controller (헤드노드)
```bash
/opt/apptainers/
-rwxr-xr-x 1 root root 511M vnc_desktop.sif
-rwxr-xr-x 1 root root 841M vnc_gnome.sif

/scratch/
drwxr-xr-x 2 koopark koopark vnc_logs
drwxr-xr-x 2 koopark koopark vnc_sandboxes
drwxr-xr-x 2 koopark koopark vnc_sessions
```

### viz-node001 (192.168.122.252)
```bash
/opt/apptainers/
-rwxr-xr-x 1 root root 511M vnc_desktop.sif
-rwxr-xr-x 1 root root 841M vnc_gnome.sif

/scratch/
drwxrwxr-x 2 koopark koopark vnc_logs
drwxr-xr-x 5 koopark koopark vnc_sandboxes
drwxrwxr-x 2 koopark koopark vnc_sessions
```

### node001, node002 (계산 노드)
```bash
/opt/apptainers/
(비어있음 - compute 이미지 없음)

/scratch/
drwxr-xr-x 2 koopark koopark vnc_logs
drwxr-xr-x 2 koopark koopark vnc_sandboxes
drwxr-xr-x 2 koopark koopark vnc_sessions
```

## 🎁 장점

### 1. 표준 준수 ⭐⭐⭐⭐⭐
- `/opt`: 읽기 전용 애플리케이션 (FHS 표준)
- `/scratch`: 임시/작업 데이터 (HPC 표준)
- 명확한 역할 분리

### 2. 보안 향상 ⭐⭐⭐⭐⭐
- 이미지 파일: root 소유, 변조 불가
- 작업 데이터: 사용자 소유, 쓰기 가능
- 권한 명확히 분리

### 3. 관리 용이성 ⭐⭐⭐⭐⭐
- 프로젝트 내에서 이미지 버전 관리
- Git으로 배포 스크립트 추적
- 노드 타입별 자동 배포

### 4. 데이터 보존 ⭐⭐⭐⭐
- 로그 파일: `/tmp` → `/scratch` (재부팅 후에도 유지)
- 디버깅 및 문제 추적 용이

### 5. 확장성 ⭐⭐⭐⭐⭐
- 새 이미지 추가: `.sif` 파일만 복사
- 자동 감지 및 배포
- 노드 타입별 이미지 관리

## 🔧 사용 방법

### 새 이미지 추가
```bash
# VNC/시각화 이미지 추가
cp new_desktop.sif apptainer/viz-node-images/

# 계산 노드 이미지 추가
cp compute_app.sif apptainer/compute-node-images/

# 배포
./deploy_apptainers.sh
```

### 이미지 업데이트만
```bash
# Apptainer 설치 스킵, 이미지만 업데이트
./deploy_apptainers.sh --update
```

### 확인
```bash
# 로컬
sudo ls -lh /opt/apptainers/

# 원격 노드
ssh koopark@192.168.122.252 'sudo ls -lh /opt/apptainers/'
```

## 📊 파일 위치 매핑

| 구분 | 이전 | 현재 | 비고 |
|------|------|------|------|
| 이미지 원본 | `/scratch/apptainers/*.sif` | `프로젝트/apptainer/viz-node-images/*.sif` | 버전 관리 가능 |
| 배포 이미지 | `/scratch/apptainers/*.sif` | `/opt/apptainers/*.sif` | root 소유, 읽기 전용 |
| 샌드박스 | `/scratch/vnc_sandboxes/` | `/scratch/vnc_sandboxes/` | 변경 없음 |
| 세션 데이터 | `/scratch/apptainers/sessions/` | `/scratch/vnc_sessions/` | 경로 명확화 |
| 로그 | `/tmp/vnc_logs/` | `/scratch/vnc_logs/` | 영구 보존 |

## 🧪 테스트 상태

### 배포 테스트 ✅
- Controller: 성공
- viz-node001: 성공
- node001: 성공
- node002: 성공

### 백엔드 재시작 ✅
- Dashboard Backend (5010): 정상 작동
- API 요청 처리: 정상

### 구조 검증 ✅
- `/opt/apptainers/`: 모든 노드 생성 완료
- `/scratch/vnc_*`: 모든 노드 생성 완료
- 권한 설정: 정상

## 📝 다음 단계

1. **VNC 세션 생성 테스트**
   - XFCE4 Desktop 세션 생성
   - GNOME Desktop 세션 생성
   - 외부 접속 확인

2. **계산 노드 이미지 추가** (선택사항)
   - 계산용 Apptainer 이미지 생성
   - `apptainer/compute-node-images/`에 배치
   - 재배포

3. **문서화**
   - 운영 매뉴얼 업데이트
   - 트러블슈팅 가이드

## 🔗 관련 파일

- [deploy_apptainers.sh](deploy_apptainers.sh) - 배포 스크립트
- [vnc_api.py](dashboard/backend_5010/vnc_api.py) - VNC API (경로 업데이트)
- [USAGE.md](USAGE.md) - 전체 사용 가이드

## ✨ 요약

Apptainer 이미지 관리 구조를 FHS 표준에 맞게 완전히 재편성했습니다. 이제 이미지는 `/opt`에서 안전하게 보관되고, 작업 데이터는 `/scratch`에서 관리됩니다. 프로젝트 내에서 이미지 버전 관리가 가능하며, 자동 배포 시스템이 구축되었습니다.

**모든 시스템이 정상 작동 중입니다! 🚀**
