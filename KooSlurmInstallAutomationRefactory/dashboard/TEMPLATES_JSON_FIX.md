# Job Templates JSON 파싱 에러 수정

## 🐛 문제 상황

Job Templates 페이지 접속 시 500 에러 발생:
```
ApiError: Expecting ',' delimiter: line 1 column 244 (char 243)
```

## 🔍 원인 분석

### 에러 메시지 해석
- **"Expecting ',' delimiter"**: JSON 파싱 중 콤마가 예상되는 위치에서 발견되지 않음
- **"line 1 column 244"**: JSON 문자열의 244번째 문자 위치에서 에러 발생

### 근본 원인
`schema.sql`의 템플릿 데이터에서 **JSON 이스케이프 처리가 잘못됨**:

```sql
-- ❌ 잘못된 이스케이프 (Before)
'{"partition": "compute", "script": "#!/bin/bash\\n#SBATCH --ntasks=32\\n\\n# LS-DYNA..."}'
```

**문제점:**
1. 이중 백슬래시 `\\n`가 데이터베이스에 그대로 저장됨
2. JSON 파서가 이를 이스케이프 시퀀스로 인식하지 못함
3. 특히 bash 스크립트의 여러 줄 문자열에서 문제 발생
4. 특수 문자(이모지 ✅, ❌)가 JSON 문자열 내부에 포함되어 파싱 오류

## ✅ 해결 방법

### 1. schema.sql 수정

**올바른 JSON 형식으로 수정:**

```sql
-- ✅ 올바른 형식 (After)
'{"partition": "group6", "script": "#!/bin/bash\n#SBATCH --ntasks=32\n\nmodule load lsdyna/R13.1.0..."}'
```

**주요 변경사항:**
- ✅ `\\n` → `\n` (단일 백슬래시)
- ✅ `\\"` → `\"` (따옴표 이스케이프 단순화)
- ✅ 이모지 제거 (✅, ❌ → 텍스트로 대체)
- ✅ `partition`: `"compute"` → `"group6"` (실제 파티션 이름)

### 2. 수정된 Templates

#### tpl-lsdyna-single
```json
{
  "partition": "group6",
  "nodes": 1,
  "cpus": 32,
  "memory": "64GB",
  "time": "24:00:00",
  "script": "#!/bin/bash\n#SBATCH --ntasks=32\n\nmodule load lsdyna/R13.1.0\n\nNPROCS=32\nMEMORY=64000000\n\necho \"LS-DYNA Single Job\"\necho \"Job ID: $SLURM_JOB_ID\"\necho \"Node: $SLURM_NODELIST\"\necho \"Cores: $NPROCS\"\n\nif [ ! -f \"$K_FILE\" ]; then\n    echo \"Error: K file not found: $K_FILE\"\n    exit 1\nfi\n\nOUTPUT_DIR=$(dirname $K_FILE)/output\nmkdir -p $OUTPUT_DIR\ncd $OUTPUT_DIR\n\nmpirun -np $NPROCS ls-dyna_mpp I=$K_FILE MEMORY=$MEMORY NCPU=$NPROCS\n\nEXIT_CODE=$?\nif [ $EXIT_CODE -eq 0 ]; then\n    echo \"LS-DYNA simulation completed successfully\"\nelse\n    echo \"LS-DYNA simulation failed with exit code $EXIT_CODE\"\nfi\nexit $EXIT_CODE"
}
```

#### tpl-lsdyna-array
```json
{
  "partition": "group6",
  "nodes": 1,
  "cpus": 16,
  "memory": "32GB",
  "time": "12:00:00",
  "script": "#!/bin/bash\n#SBATCH --ntasks=16\n\nmodule load lsdyna/R13.1.0\n\nNPROCS=16\nMEMORY=32000000\n\necho \"LS-DYNA Array Job Submission\"\necho \"Parent Job ID: $SLURM_JOB_ID\"\necho \"Total K files: ${#K_FILES[@]}\"\n\nfor K_FILE in \"${K_FILES[@]}\"; do\n    if [ ! -f \"$K_FILE\" ]; then\n        echo \"Error: K file not found: $K_FILE\"\n        exit 1\n    fi\ndone\n\nJOB_IDS=()\nfor i in \"${!K_FILES[@]}\"; do\n    K_FILE=\"${K_FILES[$i]}\"\n    BASENAME=$(basename \"$K_FILE\" .k)\n    \n    echo \"[$((i+1))/${#K_FILES[@]}] Submitting job for: $BASENAME\"\n    \n    JOB_DIR=\"/Data/Results/lsdyna_${SLURM_JOB_ID}_${i}_${BASENAME}\"\n    mkdir -p $JOB_DIR/output\n    \n    SUBMITTED_JOB_ID=$(sbatch --parsable $JOB_DIR/run_lsdyna.sh)\n    JOB_IDS+=($SUBMITTED_JOB_ID)\n    \n    echo \"Job ID: $SUBMITTED_JOB_ID\"\n    sleep 1\ndone\n\necho \"Total jobs submitted: ${#JOB_IDS[@]}\"\necho \"Job IDs: ${JOB_IDS[@]}\""
}
```

## 🔧 적용 방법

### 옵션 1: 자동 수정 스크립트 (권장) ⭐

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory

# 스크립트 실행 권한 부여
chmod +x fix_templates_db.sh
chmod +x check_template_json.py

# 데이터베이스 초기화 및 재시작
./fix_templates_db.sh
```

이 스크립트는 자동으로:
1. ✅ Backend 중지
2. ✅ 기존 DB 백업
3. ✅ DB 삭제 및 재생성
4. ✅ JSON 유효성 검증
5. ✅ Backend 재시작 (Production 모드)

### 옵션 2: 수동 적용

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory

# 1. Backend 중지
cd backend_5010
./stop.sh

# 2. DB 백업
cp database/dashboard.db database/dashboard.db.backup

# 3. DB 삭제
rm -f database/dashboard.db

# 4. DB 초기화
cd ..
python3 -c "
import sys
sys.path.insert(0, 'backend_5010')
from database import init_database
init_database()
"

# 5. Backend 재시작
cd backend_5010
export MOCK_MODE=false
./start.sh
```

## 🔎 검증 방법

### 1. API 직접 호출
```bash
# 템플릿 조회
curl -s http://localhost:5010/api/jobs/templates | jq '.'

# 예상 결과: 정상 JSON 응답
{
  "success": true,
  "mode": "production",
  "templates": [
    {
      "id": "tpl-lsdyna-single",
      "name": "LS-DYNA Single Job",
      "config": {
        "partition": "group6",
        "cpus": 32,
        ...
      }
    },
    ...
  ],
  "count": 2
}
```

### 2. JSON 유효성 검증
```bash
# 검증 스크립트 실행
python3 check_template_json.py

# 예상 출력:
# Template: LS-DYNA Single Job (tpl-lsdyna-single)
# ✅ Valid JSON
#    Partition: group6
#    CPUs: 32
```

### 3. 브라우저에서 확인
1. Job Templates 페이지 접속
2. 500 에러 없이 페이지 로드
3. 2개의 템플릿 표시:
   - LS-DYNA Single Job
   - LS-DYNA Array Job

### 4. 브라우저 콘솔 확인
- ❌ Before: `ApiError: Expecting ',' delimiter`
- ✅ After: 에러 없음

## 📊 수정 전후 비교

| 항목 | Before (문제) | After (수정) |
|------|--------------|-------------|
| **JSON 형식** | 잘못된 이스케이프 | 올바른 형식 |
| **이스케이프** | `\\n`, `\\"` | `\n`, `\"` |
| **특수 문자** | 이모지 포함 (✅, ❌) | 일반 텍스트 |
| **API 응답** | 500 Error | 200 OK |
| **파싱** | JSON 파싱 실패 | 정상 파싱 |

## 🎓 SQL에서 JSON 이스케이프 규칙

### 올바른 방법
```sql
-- ✅ 정확한 이스케이프
INSERT INTO templates (config) VALUES 
('{"script": "line1\nline2\n\"quoted\""}');
```

### 잘못된 방법
```sql
-- ❌ 이중 이스케이프 (백슬래시 두 번)
INSERT INTO templates (config) VALUES 
('{"script": "line1\\nline2\\n\\"quoted\\""}');

-- ❌ 특수 문자 (이모지 등)
INSERT INTO templates (config) VALUES 
('{"message": "✅ Success"}');  -- JSON 파서 문제 발생 가능
```

## 🚨 주의사항

1. **데이터 손실**: `fix_templates_db.sh` 실행 시 기존 데이터베이스가 삭제됨
   - 자동으로 백업 생성됨
   - 필요시 수동 백업 권장

2. **사용자 생성 템플릿**: 사용자가 만든 템플릿은 삭제됨
   - Production 환경에서는 신중히 진행

3. **Backend 재시작**: 서비스 중단 시간 발생 (1-2분)

## 📝 생성된 파일

1. ✅ `backend_5010/database/schema.sql` - 수정된 스키마
2. ✅ `check_template_json.py` - JSON 유효성 검증 스크립트
3. ✅ `fix_templates_db.sh` - 자동 수정 스크립트

## 🔄 문제 재발 방지

앞으로 `schema.sql`에 템플릿 추가 시 주의사항:

1. **JSON 이스케이프**: 단일 백슬래시 사용 (`\n`, `\"`)
2. **특수 문자 피하기**: 이모지 대신 일반 텍스트
3. **검증**: 추가 후 `check_template_json.py` 실행
4. **테스트**: 로컬에서 먼저 테스트 후 적용

---

**작성일**: 2025-10-11  
**수정 파일**:
- `backend_5010/database/schema.sql` - JSON 이스케이프 수정
- `check_template_json.py` - 신규 생성
- `fix_templates_db.sh` - 신규 생성

**해결된 에러**:
- `ApiError: Expecting ',' delimiter: line 1 column 244 (char 243)`
