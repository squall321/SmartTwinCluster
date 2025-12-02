# Phase 1 Backend Apptainer 통합 완료

> **작성일**: 2025-11-06
> **목적**: Phase 1 Backend에 Apptainer 이미지 실행 기능 추가
> **상태**: ✅ 완료

---

## 📋 수정 내역

### 수정된 파일

**파일**: `backend_5010/app.py`
**함수**: `submit_job()` (Line 613-767)

### 주요 변경사항

#### 1. apptainerImage 필드 파싱 (Line 693)

**추가된 코드**:
```python
apptainer_image = data.get('apptainerImage')  # Phase 1: Apptainer 통합
```

**목적**: Frontend에서 전송된 Apptainer 이미지 정보 추출

**데이터 구조**:
```python
{
    'id': 'python_3.11',
    'name': 'python_3.11.sif',
    'path': '/shared/apptainer/images/compute/python_3.11.sif',
    'type': 'compute',
    'version': '3.11'
}
```

#### 2. Slurm Script 생성 로직 개선 (Line 716-736)

**Before**:
```python
# 업로드된 파일 경로를 환경변수로 추가
if file_env_vars:
    f.write(f"# Uploaded File Paths\n")
    for var_name, file_path in file_env_vars.items():
        f.write(f"export {var_name}=\"{file_path}\"\n")
    f.write(f"\n")

f.write(f"{script_content}\n")  # ❌ Apptainer 처리 없음
```

**After**:
```python
# 업로드된 파일 경로를 환경변수로 추가
if file_env_vars:
    f.write(f"# Uploaded File Paths (Phase 3)\n")
    for var_name, file_path in file_env_vars.items():
        f.write(f"export {var_name}=\"{file_path}\"\n")
    f.write(f"\n")

# ✅ Phase 1: Apptainer 이미지 실행
if apptainer_image:
    image_path = apptainer_image['path']
    image_name = apptainer_image['name']
    f.write(f"# Phase 1: Apptainer Container Execution\n")
    f.write(f"echo \"========================================\"\n")
    f.write(f"echo \"Using Apptainer image: {image_name}\"\n")
    f.write(f"echo \"Image path: {image_path}\"\n")
    f.write(f"echo \"========================================\"\n")
    f.write(f"\n")
    f.write(f"# Execute script inside Apptainer container\n")
    f.write(f"apptainer exec {image_path} bash <<'APPTAINER_SCRIPT'\n")
    f.write(f"{script_content}\n")
    f.write(f"APPTAINER_SCRIPT\n")
    f.write(f"\n")
    f.write(f"echo \"Apptainer execution completed\"\n")
else:
    # Apptainer 없이 일반 실행
    f.write(f"# Direct execution (no Apptainer)\n")
    f.write(f"{script_content}\n")
```

#### 3. 로깅 개선 (Line 749-756)

**추가된 로그**:
```python
# 로깅 개선
if apptainer_image:
    print(f"✅ Job {job_id} submitted with Apptainer image: {apptainer_image['name']}")
else:
    print(f"✅ Job {job_id} submitted (no Apptainer)")

if file_env_vars:
    print(f"   📁 With {len(file_env_vars)} environment variables for uploaded files")
```

---

## 🔍 생성되는 Slurm Script 예시

### Case 1: Apptainer 이미지 있음

```bash
#!/bin/bash
#SBATCH --job-name=test_job
#SBATCH --partition=group1
#SBATCH --nodes=1
#SBATCH --cpus-per-task=64
#SBATCH --mem=16GB
#SBATCH --time=01:00:00

# Uploaded File Paths (Phase 3)
export FILE_DATA_INPUT=/shared/uploads/user01/20251106/data.csv
export INPUT=/shared/uploads/user01/20251106/data.csv

# Phase 1: Apptainer Container Execution
echo "========================================"
echo "Using Apptainer image: python_3.11.sif"
echo "Image path: /shared/apptainer/images/compute/python_3.11.sif"
echo "========================================"

# Execute script inside Apptainer container
apptainer exec /shared/apptainer/images/compute/python_3.11.sif bash <<'APPTAINER_SCRIPT'
#!/bin/bash
echo "Hello from inside Apptainer!"
python3 --version
python3 process.py --input $INPUT
APPTAINER_SCRIPT

echo "Apptainer execution completed"
```

### Case 2: Apptainer 없음 (일반 실행)

```bash
#!/bin/bash
#SBATCH --job-name=test_job
#SBATCH --partition=group1
#SBATCH --nodes=1
#SBATCH --cpus-per-task=64
#SBATCH --mem=16GB
#SBATCH --time=01:00:00

# Direct execution (no Apptainer)
#!/bin/bash
echo "Hello from host!"
hostname
date
```

---

## ✅ 통합 완성도

### Phase 1: Apptainer Images

```
Frontend: ████████████████████ 100% ✅
  ✅ ApptainerCatalog 페이지
  ✅ ApptainerSelector 컴포넌트
  ✅ useApptainerImages hook
  ✅ Job Submit 통합
  ✅ JWT 인증

Backend:  ████████████████████ 100% ✅
  ✅ GET /api/v2/apptainer/images (목록 조회)
  ✅ GET /api/v2/apptainer/images/{id} (상세 조회)
  ✅ POST /api/v2/apptainer/scan (스캔)
  ✅ Job Submit apptainerImage 처리 ⭐ (신규!)
  ✅ Slurm script에 apptainer exec 추가 ⭐ (신규!)
  ✅ JWT 검증

───────────────────────────────────────────────
Phase 1 완성도:  ████████████████████ 100% 🎉
```

---

## 🧪 테스트 방법

### 1. 자동 테스트 스크립트

**위치**: `backend_5010/test_apptainer_integration.sh`

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/backend_5010

# JWT 토큰 설정 (Auth Portal에서 발급)
export JWT_TOKEN="your_jwt_token_here"

# 테스트 실행
./test_apptainer_integration.sh
```

**테스트 항목**:
1. Backend Health Check
2. Apptainer Images API 조회
3. Job Submit with Apptainer
4. Job Submit without Apptainer

### 2. Frontend UI 테스트

```
1. 로그인
   http://localhost/dashboard
   → Auth Portal로 리다이렉트
   → 사용자 인증

2. Job Submit
   Jobs → Submit New Job

3. Apptainer 이미지 선택
   이미지 목록에서 선택 (예: python_3.11.sif)

4. Job Script 작성
   #!/bin/bash
   echo "Hello from Apptainer!"
   python3 --version

5. Submit
   Submit 버튼 클릭

6. 확인
   Backend 로그:
   sudo tail -f /var/log/dashboard_backend.log

   예상 로그:
   ✅ Job 12345 submitted with Apptainer image: python_3.11.sif
```

### 3. Production 모드 테스트

```bash
# MOCK_MODE 비활성화
export MOCK_MODE=false

# Backend 재시작
sudo systemctl restart dashboard_backend

# Job Submit 테스트
# Frontend에서 Job 제출

# Slurm Queue 확인
squeue -u $USER

# Job 출력 확인
tail -f /scratch/$USER/slurm-<jobid>.out

# 예상 출력:
========================================
Using Apptainer image: python_3.11.sif
Image path: /shared/apptainer/images/compute/python_3.11.sif
========================================
Hello from Apptainer!
Python 3.11.5
Apptainer execution completed
```

---

## 🎯 주요 기능

### 1. 자동 Apptainer 감싸기

사용자가 작성한 Job Script가 자동으로 Apptainer Container 안에서 실행됩니다.

**사용자 입력**:
```bash
#!/bin/bash
python3 train.py
```

**실제 실행** (Backend가 자동 생성):
```bash
apptainer exec /path/to/image.sif bash <<'APPTAINER_SCRIPT'
#!/bin/bash
python3 train.py
APPTAINER_SCRIPT
```

### 2. 환경변수 유지

업로드된 파일 환경변수가 Container 내부에서도 사용 가능합니다.

```bash
# Host에서 환경변수 설정
export INPUT=/shared/uploads/data.csv

# Container 내부에서 사용
apptainer exec image.sif bash <<'SCRIPT'
python3 process.py --input $INPUT  # ✅ 정상 작동
SCRIPT
```

### 3. Heredoc 사용

`bash <<'APPTAINER_SCRIPT'` 구문으로 스크립트를 안전하게 전달합니다.

**장점**:
- 특수문자 이스케이프 불필요
- 여러 줄 스크립트 지원
- 변수 확장 방지 (싱글 쿼트)

---

## 📊 전체 시스템 완성도

```
Phase 1: Apptainer Images       ████████████████████ 100% ✅
Phase 2: Templates               ████████████████████ 100% ✅
Phase 3: File Upload             ████████████████████ 100% ✅
Job Submit Integration           ████████████████████ 100% ✅
JWT 인증                         ████████████████████ 100% ✅

───────────────────────────────────────────────
전체 완성도:                      ████████████████████ 100% 🎉
```

---

## 🚀 배포 방법

### 1. Backend만 재시작

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/backend_5010

# 변경사항 확인
git diff app.py

# Backend 재시작
sudo systemctl restart dashboard_backend

# 로그 확인
sudo tail -f /var/log/dashboard_backend.log
```

### 2. 전체 시스템 재배포 (권장)

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory

# 전체 클러스터 재설치
./setup_cluster_full_multihead.sh

# 또는 Frontend + Backend만
cd dashboard/frontend_3010
npm run build
sudo cp -r dist/* /var/www/html/dashboard/

sudo systemctl restart dashboard_backend
sudo systemctl reload nginx
```

---

## 📝 관련 문서

1. **[PHASE_BY_PHASE_STATUS.md](PHASE_BY_PHASE_STATUS.md)** - Phase별 상세 현황
2. **[PHASE_1_2_3_INTEGRATION_COMPLETE.md](PHASE_1_2_3_INTEGRATION_COMPLETE.md)** - Frontend 통합
3. **[JWT_INTEGRATION_PLAN.md](JWT_INTEGRATION_PLAN.md)** - JWT 인증 계획
4. **[NEXT_STEPS.md](NEXT_STEPS.md)** - 다음 단계 가이드

---

## 🎉 완료!

**Phase 1 Backend 통합 100% 완료!**

이제 사용자는:
1. ✅ Template 선택 → 파라미터 자동 설정
2. ✅ **Apptainer 이미지 선택** → Container 자동 실행 ⭐
3. ✅ 파일 업로드 → 환경변수 자동 생성
4. ✅ Job Submit → Slurm에 제출

**모든 Phase가 완벽하게 통합되었습니다!** 🚀

---

**작성일**: 2025-11-06
**수정 파일**: `backend_5010/app.py` (Line 693, 716-736, 749-756)
**테스트 스크립트**: `backend_5010/test_apptainer_integration.sh`
**상태**: ✅ 완료
