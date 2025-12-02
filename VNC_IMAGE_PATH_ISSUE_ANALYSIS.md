# VNC Image Path Issue - Root Cause Analysis

## 문제 현상

### 1. 증상
- `/vnc` 페이지에서 이미지 리스트가 표시되지 않음
- VNC 접속 시도 시 에러 발생:
  ```
  Image file not found: /opt/apptainers/vnc_desktop.sif
  ```

### 2. 사용자 보고
- viz-node에는 해당 위치에 sif 파일이 존재한다고 확인됨
- compute node의 apptainer 배포 작업 중 문제 발생

---

## 현재 상태 확인

### Headnode (Backend 실행 위치)
```bash
$ ls -la /opt/apptainers/
total 28
drwxr-xr-x  3 root root 4096 11월  7 23:27 .
drwxr-xr-x 12 root root 4096 11월  5 04:53 ..
drwxr-xr-x  3 root root 4096 10월 26 04:16 apps
-rw-r--r--  1 root root  918 11월  5 03:16 KooSimulationPython313.sif.json
-rw-r--r--  1 root root  854 11월  5 03:17 vnc_desktop.sif.json
-rw-r--r--  1 root root  974 11월  5 03:18 vnc_gnome_lsprepost.sif.json
-rw-r--r--  1 root root  891 11월  5 03:17 vnc_gnome.sif.json
```
**결과**: ❌ .sif 파일 없음, JSON 메타데이터만 존재

### viz-node001 (실제 VNC 실행 위치)
```bash
$ ssh viz-node001 "ls -la /opt/apptainers/"
total 2671488
drwxr-xr-x 3 root    root          4096 Nov  4 21:50 .
drwxr-xr-x 4 root    root          4096 Oct 31 06:53 ..
drwxr-xr-x 3 koopark koopark       4096 Oct 24 08:13 apps
-rwxr-xr-x 1 root    root     535367680 Nov  3 23:27 vnc_desktop.sif
-rwxr-xr-x 1 root    root     880820224 Nov  3 23:27 vnc_gnome.sif
-rwxr-xr-x 1 root    root    1319391232 Oct 23 21:44 vnc_gnome_lsprepost.sif

$ ssh viz-node001 "ls /opt/apptainers/*.json"
ls: cannot access '/opt/apptainers/*.json': No such file or directory
```
**결과**: ✅ .sif 파일 존재, ❌ JSON 메타데이터 없음

---

## 근본 원인 분석

### 문제 1: 이미지 목록 조회 실패

**코드 위치**: `dashboard/backend_5010/vnc_api.py:832`

```python
@vnc_bp.route('/images', methods=['GET'])
@jwt_required
def list_vnc_images():
    images_list = []

    for image_id, config in VNC_IMAGES.items():
        image_info = {
            'id': image_id,
            'name': config['name'],
            'description': config['description'],
            'icon': config.get('icon', '🖥️'),
            'default': config.get('default', False),
            'available': os.path.exists(config['sif_path'])  # ❌ 문제!
        }
        images_list.append(image_info)

    return jsonify({'images': images_list}), 200
```

**문제점**:
- `os.path.exists(config['sif_path'])` - **Headnode**에서 파일 존재 확인
- `config['sif_path']` = `/opt/apptainers/vnc_desktop.sif`
- Headnode에는 .sif 파일이 없으므로 → `available: false`
- Frontend는 `available: false`인 이미지를 리스트에 표시하지 않음

### 문제 2: VNC 세션 생성 실패

**코드 위치**: `dashboard/backend_5010/vnc_api.py:518-519`

```python
@vnc_bp.route('/sessions', methods=['POST'])
@jwt_required
def create_vnc_session():
    # ...

    image_config = VNC_IMAGES[image_id]
    sif_image_path = image_config['sif_path']

    # SIF 이미지 파일 존재 확인
    if not os.path.exists(sif_image_path):  # ❌ 문제!
        return jsonify({'error': f'Image file not found: {sif_image_path}'}), 500

    # ...
```

**문제점**:
- VNC 세션 생성 시 **Headnode**에서 파일 존재 확인
- Headnode에 .sif 파일이 없으므로 → 에러 반환
- **실제 Job은 viz-node에서 실행되는데**, Headnode에서 미리 체크하다가 막힘

### VNC_IMAGES 설정

**코드 위치**: `dashboard/backend_5010/vnc_api.py:55-83`

```python
# VNC 이미지 및 작업 디렉토리 경로 (새 구조)
VNC_IMAGES_DIR = "/opt/apptainers"           # 읽기 전용 이미지 저장소

VNC_IMAGES = {
    "xfce4": {
        "name": "XFCE4 Desktop",
        "description": "Lightweight desktop environment with XFCE4",
        "sif_path": f"{VNC_IMAGES_DIR}/vnc_desktop.sif",  # /opt/apptainers/vnc_desktop.sif
        "start_script": "/opt/scripts/start_vnc.sh",
        "desktop_env": "XFCE4",
        "icon": "🖥️",
        "default": True
    },
    "gnome": {
        "name": "GNOME Desktop",
        "description": "Full-featured Ubuntu GNOME desktop environment",
        "sif_path": f"{VNC_IMAGES_DIR}/vnc_gnome.sif",
        "start_script": "/opt/scripts/start_vnc_gnome.sh",
        "desktop_env": "GNOME",
        "icon": "🎨",
        "default": False
    },
    "gnome_lsprepost": {
        "name": "GNOME + LS-PrePost 4.12",
        "description": "GNOME Desktop with LS-PrePost 4.12.8 pre-installed",
        "sif_path": f"{VNC_IMAGES_DIR}/vnc_gnome_lsprepost.sif",
        "start_script": "/opt/scripts/start_vnc_gnome.sh",
        "desktop_env": "GNOME",
        "icon": "🔧",
        "default": False
    }
}
```

---

## 왜 이런 문제가 발생했는가?

### 이전 구조 (정상 작동)
```
Headnode:
  /opt/apptainers/
    ├── vnc_desktop.sif          ✅ 파일 존재
    ├── vnc_gnome.sif             ✅ 파일 존재
    └── vnc_gnome_lsprepost.sif   ✅ 파일 존재

viz-node001:
  /opt/apptainers/
    ├── vnc_desktop.sif          ✅ 파일 존재
    ├── vnc_gnome.sif             ✅ 파일 존재
    └── vnc_gnome_lsprepost.sif   ✅ 파일 존재
```
- Backend(Headnode)에서 파일 존재 확인 → ✅ 성공
- Job은 viz-node에서 실행 → ✅ 파일 있음

### 현재 구조 (문제 발생)
```
Headnode:
  /opt/apptainers/
    ├── vnc_desktop.sif.json          ✅ 메타데이터만
    ├── vnc_gnome.sif.json            ✅ 메타데이터만
    └── vnc_gnome_lsprepost.sif.json  ✅ 메타데이터만

viz-node001:
  /opt/apptainers/
    ├── vnc_desktop.sif          ✅ 실제 파일
    ├── vnc_gnome.sif            ✅ 실제 파일
    └── vnc_gnome_lsprepost.sif  ✅ 실제 파일
    └── (no JSON files)
```
- Backend(Headnode)에서 파일 존재 확인 → ❌ 실패 (.sif 없음)
- Job은 viz-node에서 실행될 예정 → ✅ 파일 있음 (도달 못함)

### 구조 변경 원인 추정

**APPTAINER_RESTRUCTURE.md** 문서에 따르면, compute node의 apptainer 배포 작업 중:
1. **Registry 기반 메타데이터 관리 도입**
   - JSON 메타데이터를 별도로 관리
   - DB 기반 이미지 조회 시스템 구축

2. **Node 타입별 이미지 분리**
   - viz-node: viz 전용 이미지 (.sif 파일)
   - compute-node: compute 전용 이미지 (.sif 파일)
   - headnode: 메타데이터 관리 (JSON 파일)

3. **문제: VNC API 코드는 업데이트되지 않음**
   - `vnc_api.py`는 여전히 로컬 파일 시스템 확인 방식 사용
   - 새로운 Registry 기반 조회로 전환되지 않음

---

## 실행 흐름 다이어그램

### 이미지 목록 조회 시

```
┌─────────────────────────────────────────────────────────────┐
│ Frontend (/vnc page)                                        │
│ GET /api/vnc/images                                         │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ Backend (Headnode)                                          │
│ vnc_api.py:list_vnc_images()                                │
│                                                             │
│ for image_id, config in VNC_IMAGES.items():                │
│     available = os.path.exists(config['sif_path'])         │
│                  ▼                                          │
│     Check: /opt/apptainers/vnc_desktop.sif on Headnode     │
│     Result: ❌ File not found                               │
│     Return: available=false                                 │
└─────────────────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ Frontend                                                    │
│ Filters out images with available=false                    │
│ Result: Empty list displayed                               │
└─────────────────────────────────────────────────────────────┘
```

### VNC 세션 생성 시

```
┌─────────────────────────────────────────────────────────────┐
│ Frontend (/vnc page)                                        │
│ User clicks "Connect" (shouldn't reach here if list empty) │
│ POST /api/vnc/sessions                                      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ Backend (Headnode)                                          │
│ vnc_api.py:create_vnc_session()                             │
│                                                             │
│ sif_image_path = VNC_IMAGES[image_id]['sif_path']          │
│                  ▼                                          │
│ if not os.path.exists(sif_image_path):  # Line 518         │
│     Check: /opt/apptainers/vnc_desktop.sif on Headnode     │
│     Result: ❌ File not found                               │
│     return error: "Image file not found: ..."              │
│     ❌ Job never submitted to viz-node                      │
└─────────────────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ Frontend                                                    │
│ Displays error to user:                                    │
│ "Image file not found: /opt/apptainers/vnc_desktop.sif"    │
└─────────────────────────────────────────────────────────────┘
```

**실제 Job이 실행될 viz-node에는 파일이 있지만, 도달조차 하지 못함!**

---

## 해결 방안 (수정하지 않고 분석만)

### 방안 1: Headnode에 .sif 파일 복사 ⚡ (Quick Fix)

**장점**:
- 코드 수정 불필요
- 즉시 적용 가능

**단점**:
- 파일 중복 (각 viz 이미지는 500MB ~ 1.3GB)
- 3개 이미지 = 약 2.7GB 중복 저장
- 관리 포인트 증가 (동기화 필요)

**구현**:
```bash
# Headnode에서 실행
scp viz-node001:/opt/apptainers/vnc_desktop.sif /opt/apptainers/
scp viz-node001:/opt/apptainers/vnc_gnome.sif /opt/apptainers/
scp viz-node001:/opt/apptainers/vnc_gnome_lsprepost.sif /opt/apptainers/
```

---

### 방안 2: Backend 코드 수정 - SSH 원격 확인 🔧 (Proper Fix)

**장점**:
- 파일 중복 없음
- 실제 실행 노드의 상태 확인
- 정확한 가용성 체크

**단점**:
- 코드 수정 필요
- SSH 오버헤드 (매번 확인 시)

**구현**:
```python
# vnc_api.py 수정

def check_image_exists_on_viz_node(sif_path):
    """viz-node에서 이미지 파일 존재 확인"""
    try:
        result = subprocess.run(
            ['ssh', 'viz-node001', f'test -f {sif_path} && echo "exists"'],
            capture_output=True,
            text=True,
            timeout=5
        )
        return 'exists' in result.stdout
    except:
        return False

# list_vnc_images() 수정
@vnc_bp.route('/images', methods=['GET'])
@jwt_required
def list_vnc_images():
    images_list = []

    for image_id, config in VNC_IMAGES.items():
        image_info = {
            'id': image_id,
            'name': config['name'],
            'description': config['description'],
            'icon': config.get('icon', '🖥️'),
            'default': config.get('default', False),
            'available': check_image_exists_on_viz_node(config['sif_path'])  # 수정
        }
        images_list.append(image_info)

    return jsonify({'images': images_list}), 200

# create_vnc_session() 수정 (518번 라인 제거 또는 주석)
@vnc_bp.route('/sessions', methods=['POST'])
@jwt_required
def create_vnc_session():
    # ...

    # ❌ 제거: Headnode에서의 체크는 무의미
    # if not os.path.exists(sif_image_path):
    #     return jsonify({'error': f'Image file not found: {sif_image_path}'}), 500

    # ✅ 추가: viz-node에서 확인 (선택사항)
    if not check_image_exists_on_viz_node(sif_image_path):
        return jsonify({'error': f'Image file not found on viz-node: {sif_image_path}'}), 500

    # Job 제출 계속...
```

---

### 방안 3: DB/Registry 기반 조회로 전환 🚀 (Modern Approach)

**장점**:
- 중앙화된 이미지 관리
- 확장성 좋음
- 다중 노드 지원
- 메타데이터와 통합

**단점**:
- 대규모 리팩토링 필요
- ApptainerRegistryService와 통합 필요

**구현**:
```python
# vnc_api.py에 ApptainerRegistryService 통합

from apptainer_service_v2 import ApptainerRegistryService

# 이미지 조회를 DB에서
@vnc_bp.route('/images', methods=['GET'])
@jwt_required
def list_vnc_images():
    service = get_apptainer_service()

    # viz 타입 이미지만 조회
    viz_images = service.list_images(
        partition='viz',
        type='viz',
        is_active=True
    )

    images_list = []
    for img in viz_images:
        # vnc_desktop.sif, vnc_gnome.sif 등 VNC 이미지만 필터
        if 'vnc' in img.name.lower():
            image_info = {
                'id': img.id,
                'name': img.metadata.get('display_name', img.name),
                'description': img.metadata.get('description', ''),
                'icon': '🖥️',  # 메타데이터에서 가져올 수도 있음
                'default': 'vnc_desktop' in img.name,
                'available': img.is_active
            }
            images_list.append(image_info)

    return jsonify({'images': images_list}), 200
```

---

## 추천 해결 순서

### 단기 (즉시 해결)
1. **방안 1 적용**: Headnode에 .sif 파일 복사
   - 빠른 복구를 위해 임시로 적용
   - 사용자가 즉시 VNC 사용 가능

### 중기 (코드 개선)
2. **방안 2 적용**: SSH 원격 확인 로직 추가
   - 파일 중복 제거
   - 정확한 가용성 체크

### 장기 (시스템 개선)
3. **방안 3 적용**: Registry 기반으로 전환
   - `apptainer_service_v2` 통합
   - 전체 시스템 일관성 확보

---

## 관련 파일 및 라인

### Backend 파일
- `dashboard/backend_5010/vnc_api.py`
  - Line 49-52: VNC 경로 설정
  - Line 55-83: VNC_IMAGES 딕셔너리
  - Line 832: 이미지 목록 조회 시 `os.path.exists()` 체크
  - Line 518-519: 세션 생성 시 `os.path.exists()` 체크

### 관련 문서
- `APPTAINER_RESTRUCTURE.md`: Apptainer 구조 변경 설명
- `apptainer/METADATA_README.md`: 메타데이터 관리 방식
- `dashboard/backend_5010/apptainer_api.py`: Registry 기반 API

### Frontend 파일 (예상)
- `dashboard/auth_portal_4431/src/pages/VNCPage.tsx`: VNC 페이지
- `dashboard/frontend_3010/src/components/VNCSessionManager.tsx`: VNC 세션 관리

---

## 결론

**문제의 핵심**:
- Compute node apptainer 배포 작업 중 구조 변경 (Registry 도입)
- Headnode: 메타데이터(JSON)만, viz-node: 실제 파일(.sif)만 보유
- Backend 코드는 여전히 Headnode의 로컬 파일시스템 확인
- → 파일을 찾을 수 없어 이미지 목록이 비어있고, 세션 생성도 실패

**즉시 조치 필요**:
- 방안 1 (파일 복사) 또는 방안 2 (SSH 확인)로 빠른 복구

**근본적 해결**:
- VNC API를 Registry 기반으로 리팩토링 (방안 3)
- 전체 시스템의 일관성 확보

---

**작성일**: 2025-11-13
**작성자**: Claude
**분석 대상 버전**: Dashboard v4.4.0+
