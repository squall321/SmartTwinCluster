# 다음 단계 (Next Steps)

> **작성일**: 2025-11-06
> **현재 상태**: Phase 1-2-3 Frontend 통합 + JWT 인증 완료
> **완성도**: Frontend 100% ✅ | Backend 통합 대기 ⏳

---

## ✅ 완료된 작업

### Phase 1: Apptainer Images Frontend
- ✅ ApptainerCatalog 페이지
- ✅ ApptainerSelector 컴포넌트
- ✅ useApptainerImages hook
- ✅ JWT 인증 통합

### Phase 2: Templates Frontend
- ✅ TemplateCatalog 페이지
- ✅ TemplateBrowserModal 컴포넌트
- ✅ useTemplates hook
- ✅ JWT 인증 통합

### Phase 3: File Upload Frontend
- ✅ FileUploadPage 페이지
- ✅ UnifiedUploader 컴포넌트
- ✅ ChunkUploader 유틸리티
- ✅ JWT 인증 통합

### Phase 1-2-3 통합
- ✅ Job Submit Modal에 모든 Phase 통합
- ✅ Apptainer 이미지 선택
- ✅ Template 브라우저 & 자동 설정
- ✅ 파일 업로드 (최대 50GB)
- ✅ JWT 인증 100% 일관성
- ✅ 빌드 성공
- ✅ 문서 완료

---

## 🎯 다음 해야 할 일

### 1. 배포 및 테스트 (즉시 실행 가능)

#### 1.1 Frontend 배포
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory

# Option 1: 전체 클러스터 재설치 (권장)
./setup_cluster_full_multihead.sh

# Option 2: Frontend만 수동 배포
cd dashboard/frontend_3010
npm run build
sudo cp -r dist/* /var/www/html/dashboard/
sudo systemctl restart nginx
```

#### 1.2 통합 테스트
```
테스트 시나리오:

1. 로그인 플로우
   - Auth Portal (http://localhost:4431) 접속
   - 사용자 로그인 (예: admin / password)
   - JWT 토큰 발급 확인
   - Dashboard로 리다이렉트 확인

2. Phase 1 단독 테스트
   - Sidebar → "Apptainer Images" 클릭
   - 이미지 목록 로딩 확인
   - 검색/필터 기능 확인
   - JWT 헤더 포함 확인 (브라우저 DevTools Network 탭)

3. Phase 2 단독 테스트
   - Sidebar → "Job Templates" 클릭
   - 템플릿 목록 로딩 확인
   - 카테고리별 필터링 확인
   - 템플릿 상세 모달 확인
   - JWT 헤더 포함 확인

4. Phase 3 단독 테스트
   - Sidebar → "File Upload" 클릭
   - 파일 드래그 앤 드롭 확인
   - 청크 업로드 진행률 확인
   - 업로드 완료 확인
   - JWT 헤더 포함 확인

5. 통합 Job Submit 플로우 (핵심!)
   - Sidebar → "Jobs" → "Submit New Job" 클릭

   a. Template 선택
      - "Browse Templates" 버튼 클릭
      - Template 선택 (예: OpenFOAM)
      - Job 파라미터 자동 설정 확인

   b. Apptainer 이미지 선택
      - 이미지 목록 표시 확인
      - 파티션에 맞는 필터링 확인
      - 이미지 선택

   c. 파일 업로드
      - 파일 드래그 앤 드롭
      - 청크 업로드 확인
      - Template 파일 검증 확인

   d. Job 파라미터 설정
      - Partition 선택
      - Resource Configuration 선택
      - Job Script 확인

   e. Job Submit
      - "Submit Job" 버튼 클릭
      - JWT 포함 확인 (DevTools Network 탭)
      - 성공 메시지 확인
      - Job ID 반환 확인

6. JWT 만료 시나리오
   - localStorage에서 jwt_token 삭제
   - API 호출 시도
   - 401 에러 확인
   - Auth Portal 리다이렉트 확인
```

---

### 2. Backend API 통합 확인 (중요!)

현재 Frontend는 완성되었지만, **Backend가 준비되어 있어야 합니다**.

#### 2.1 확인할 Backend API 엔드포인트

##### Phase 1: Apptainer API
```
✅ GET /api/v2/apptainer/images
✅ GET /api/v2/apptainer/images/{id}
✅ POST /api/v2/apptainer/scan

필수 요구사항:
- JWT 검증 (@jwt_required 데코레이터)
- 파티션별 필터링 지원 (?partition=compute)
- 이미지 메타데이터 반환 (name, path, size, version, apps 등)
```

##### Phase 2: Templates API
```
✅ GET /api/v2/templates
✅ GET /api/v2/templates/{id}
✅ POST /api/v2/templates/scan

필수 요구사항:
- JWT 검증
- 카테고리/소스별 필터링 지원 (?category=cfd&source=official)
- YAML 파일 파싱
- FilesSchema, ApptainerConfig 포함
```

##### Phase 3: File Upload API
```
✅ POST /api/v2/files/upload/init
✅ POST /api/v2/files/upload/chunk
✅ POST /api/v2/files/upload/complete
✅ DELETE /api/v2/files/upload/{upload_id}

필수 요구사항:
- JWT 검증
- 청크 업로드 지원 (5MB)
- 파일 타입 자동 분류
- job_id 연결
```

##### Job Submit API (수정 필요!)
```
⚠️ POST /api/slurm/jobs/submit

Frontend 요청 데이터:
{
  jobName: string,
  partition: string,
  nodes: number,
  cpus: number,
  memory: string,
  time: string,
  script: string,
  files: UploadedFile[],
  jobId: string,

  // 새로 추가된 필드!
  apptainerImage?: {
    id: string,
    name: string,
    path: string,
    type: string,
    version: string
  }
}

Backend 처리 필요:
1. JWT에서 사용자 정보 추출
   current_user = get_jwt_identity()

2. Apptainer 이미지 처리
   if apptainerImage:
       # Slurm script에 apptainer exec 명령 추가
       script = generate_apptainer_script(apptainerImage, original_script)

3. 업로드된 파일 경로 환경변수 생성
   env_vars = generate_file_env_vars(files, job_id)

4. Slurm sbatch 실행
   result = submit_to_slurm(script, env_vars, user=current_user)

5. Job 정보 DB 저장
   save_job_info(job_id, current_user, apptainerImage, files)
```

#### 2.2 Backend 수정 예시 (Python/Flask)

```python
# backend/api/slurm.py

from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity

api = Blueprint('slurm', __name__)

@api.route('/api/slurm/jobs/submit', methods=['POST'])
@jwt_required()  # ✅ JWT 검증 필수!
def submit_job():
    # JWT에서 사용자 정보 추출
    current_user = get_jwt_identity()

    data = request.json

    # 새로 추가된 apptainerImage 필드 처리
    apptainer_image = data.get('apptainerImage')
    job_script = data['script']

    # Apptainer 이미지가 지정된 경우 스크립트 수정
    if apptainer_image:
        image_path = apptainer_image['path']
        # 스크립트를 apptainer exec으로 감싸기
        job_script = f"""#!/bin/bash
#SBATCH --job-name={data['jobName']}
#SBATCH --partition={data['partition']}
#SBATCH --nodes={data['nodes']}
#SBATCH --ntasks-per-node={data['cpus']}
#SBATCH --mem={data['memory']}
#SBATCH --time={data['time']}

# Apptainer Container 실행
apptainer exec {image_path} bash <<'APPTAINER_SCRIPT'
{job_script}
APPTAINER_SCRIPT
"""

    # 업로드된 파일 경로를 환경변수로 전달
    env_vars = {}
    if 'files' in data:
        for i, file_info in enumerate(data['files']):
            env_vars[f'INPUT_FILE_{i}'] = file_info['storage_path']

    # Slurm에 Job 제출
    try:
        result = subprocess.run(
            ['sbatch'],
            input=job_script.encode(),
            capture_output=True,
            env={**os.environ, **env_vars}
        )

        # Job ID 추출 (예: "Submitted batch job 12345")
        output = result.stdout.decode()
        job_id = extract_job_id(output)

        # DB에 Job 정보 저장
        save_job_to_db(
            job_id=job_id,
            user=current_user,
            apptainer_image=apptainer_image,
            files=data.get('files', []),
            params=data
        )

        return jsonify({
            'success': True,
            'jobId': job_id,
            'message': f'Job {job_id} submitted successfully'
        }), 200

    except Exception as e:
        return jsonify({
            'success': False,
            'message': f'Failed to submit job: {str(e)}'
        }), 500
```

---

### 3. Backend 테스트 (Backend 수정 후)

```bash
# JWT 토큰 발급 (Auth Portal 통해 얻거나)
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

# Job Submit API 테스트
curl -X POST http://localhost:5000/api/slurm/jobs/submit \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "jobName": "test_job",
    "partition": "group1",
    "nodes": 1,
    "cpus": 64,
    "memory": "16GB",
    "time": "01:00:00",
    "script": "#!/bin/bash\necho Hello World",
    "jobId": "tmp-1234567890",
    "apptainerImage": {
      "id": "python_3.11",
      "name": "python_3.11.sif",
      "path": "/shared/apptainer/images/compute/python_3.11.sif",
      "type": "compute",
      "version": "3.11"
    }
  }'

# 예상 응답
{
  "success": true,
  "jobId": "12345",
  "message": "Job 12345 submitted successfully"
}

# JWT 없이 테스트 (401 에러 확인)
curl -X POST http://localhost:5000/api/slurm/jobs/submit \
  -H "Content-Type: application/json" \
  -d '{"jobName": "test"}'

# 예상 응답
{
  "msg": "Missing Authorization Header"
}
```

---

### 4. 문서 작성 (선택사항)

#### 4.1 사용자 가이드
```markdown
# Job Submit 사용 가이드

## 1. 로그인
1. http://localhost/dashboard 접속
2. Auth Portal로 리다이렉트
3. 사용자 인증 정보 입력

## 2. Template 기반 Job 제출
1. Jobs → Submit New Job
2. "Browse Templates" 클릭
3. 원하는 템플릿 선택 (예: OpenFOAM)
4. Apptainer 이미지 선택
5. 필요한 파일 업로드
6. Job 파라미터 확인
7. Submit

## 3. 사용자 정의 Job 제출
...
```

#### 4.2 관리자 가이드
```markdown
# 관리자 가이드

## Template 추가
1. /shared/templates/official/ 디렉토리에 YAML 파일 생성
2. Dashboard → Job Templates → Scan 버튼 클릭

## Apptainer 이미지 추가
1. /shared/apptainer/images/compute/ 또는 viz/ 디렉토리에 .sif 파일 배치
2. Dashboard → Apptainer Images → Scan 버튼 클릭

## 사용자 권한 관리
...
```

---

### 5. 성능 최적화 (선택사항)

#### 5.1 Frontend 번들 크기 최적화
```bash
# 현재: 1,484 KB (gzip: 384 KB)
# 목표: 500 KB 이하

# 방법:
# 1. 코드 스플리팅
# 2. 동적 import()
# 3. Tree shaking
# 4. Lazy loading
```

#### 5.2 API 캐싱 전략
```typescript
// 이미 구현됨:
// - Template 목록: 5분 캐시
// - Apptainer 이미지: 5분 캐시
// - Dashboard 데이터: 캐시 없음 (실시간)

// 개선 가능:
// - Job 목록: 30초 캐시
// - 사용자 정보: 10분 캐시
```

---

### 6. 추가 기능 구현 (선택사항)

#### 6.1 Job 모니터링 강화
- 실시간 로그 스트리밍
- Job 리소스 사용률 그래프
- Job 의존성 시각화

#### 6.2 Template 고급 기능
- Template 버전 관리
- Template 공유 (community)
- Template 즐겨찾기

#### 6.3 파일 관리
- 업로드된 파일 브라우저
- 파일 미리보기
- 파일 공유

#### 6.4 알림 시스템
- Job 완료 알림 (이메일, 브라우저 알림)
- 리소스 부족 알림
- 에러 알림

---

## 📋 우선순위

### 🔴 Critical (즉시 실행)
1. **Frontend 배포**: `./setup_cluster_full_multihead.sh`
2. **통합 테스트**: Job Submit 플로우 전체 테스트
3. **Backend API 확인**: JWT 검증 및 apptainerImage 처리

### 🟡 Important (1주일 내)
4. **Backend Job Submit 수정**: Apptainer 이미지 통합
5. **End-to-End 테스트**: Frontend → Backend → Slurm
6. **에러 처리 개선**: 사용자 친화적 에러 메시지

### 🟢 Optional (시간 여유시)
7. **문서 작성**: 사용자/관리자 가이드
8. **성능 최적화**: 번들 크기, 캐싱
9. **추가 기능**: 모니터링, 알림 등

---

## 🎯 최종 목표

```
완전히 통합된 HPC Job Submit 시스템

사용자 → Auth Portal → Dashboard
  ↓
Job Submit Modal
  ├─ Template 선택 (Phase 2)
  ├─ Apptainer 이미지 선택 (Phase 1)
  ├─ 파일 업로드 (Phase 3)
  └─ Job Submit (JWT 인증)
      ↓
Backend API (JWT 검증)
  ↓
Slurm Cluster (sbatch)
  ↓
Job 실행 (Apptainer Container)
  ↓
결과 확인 (Dashboard)
```

**현재 상태**: Frontend 100% 완료 ✅
**다음 단계**: Backend 통합 & 테스트 ⏳

---

## 📞 지원

문제 발생 시:
1. 빌드 에러 → [FRONTEND_DEVELOPMENT_RULES.md](FRONTEND_DEVELOPMENT_RULES.md) 참고
2. JWT 에러 → [JWT_INTEGRATION_PLAN.md](JWT_INTEGRATION_PLAN.md) 참고
3. 통합 이슈 → [PHASE_1_2_3_INTEGRATION_COMPLETE.md](PHASE_1_2_3_INTEGRATION_COMPLETE.md) 참고

---

**작성**: 2025-11-06
**상태**: Frontend 완료, Backend 통합 대기
**다음 리뷰**: Backend API 통합 완료 후
