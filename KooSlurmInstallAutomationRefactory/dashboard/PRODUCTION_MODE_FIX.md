# Job Templates Production 모드 문제 해결

## 🐛 문제 상황

Production 모드에서 Job Templates를 불러오지 못하고 Mock 데이터로 표시되는 문제가 발생했습니다.

### 증상
- 백엔드 로그에 `⚠️  Running in MOCK MODE`로 표시됨
- Job Templates API가 Mock 데이터만 반환
- Production 데이터베이스의 템플릿을 읽지 못함

## 🔍 원인 분석

### 확인된 문제점
1. **Backend가 Mock 모드로 실행 중**
   ```
   ⚠️  Running in MOCK MODE - No actual Slurm commands will be executed
   Mode: 🎭 MOCK (Demo)
   ```

2. **로그 확인 결과**
   ```bash
   tail -f backend_5010/backend.log | head -10
   ```
   - 백엔드가 MOCK_MODE=true로 시작됨
   - 환경변수가 제대로 전달되지 않음

### 왜 발생했나?
- `start_all.sh`에서 `export MOCK_MODE=false` 설정
- 하지만 이미 실행 중인 프로세스는 환경변수를 업데이트하지 않음
- 서비스 재시작 없이 코드만 수정했기 때문

## ✅ 해결 방법

### 방법 1: 간편한 재시작 스크립트 사용 (권장)

새로 생성된 `restart_production.sh` 스크립트를 사용:

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory

# 스크립트 실행 권한 부여
chmod +x restart_production.sh

# Production 모드로 재시작
./restart_production.sh
```

이 스크립트는 다음을 자동으로 수행합니다:
1. ✅ 모든 서비스 중지
2. ✅ 포트 강제 정리
3. ✅ PID 파일 삭제
4. ✅ MOCK_MODE=false 설정
5. ✅ 모든 서비스 재시작

### 방법 2: 수동 재시작

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory

# 1. 모든 서비스 중지
./stop_all.sh

# 2. 포트 확인 및 강제 종료
for PORT in 3010 5010 5011 9100 9090; do
    lsof -ti :$PORT | xargs -r kill -9
done

# 3. 짧은 대기
sleep 2

# 4. Production 모드로 시작
export MOCK_MODE=false
./start_all.sh
```

## 🔎 검증 방법

### 1. API 응답 확인
```bash
# Templates API 모드 확인
curl -s http://localhost:5010/api/jobs/templates | jq '.mode'
# 출력 예상: "production"

# 전체 응답 확인
curl -s http://localhost:5010/api/jobs/templates | jq '.'
```

### 2. 로그 확인
```bash
# Backend 로그에서 모드 확인
tail -f backend_5010/backend.log | grep -i "running in"

# 예상 출력:
# ✅ Running in PRODUCTION MODE - Real Slurm commands will be executed
```

### 3. 브라우저에서 확인
1. 브라우저 개발자 도구(F12) 열기
2. Network 탭에서 `/api/jobs/templates` 요청 확인
3. Response의 `mode` 필드가 `"production"`인지 확인

## 📋 Production 모드 템플릿 확인

Production 모드에서는 데이터베이스의 템플릿을 사용합니다.

### 데이터베이스 템플릿 확인
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory

# 템플릿 개수 확인
python3 check_db.py
```

### 기본 템플릿 (schema.sql)
Production 모드 초기 템플릿:
- ✅ `tpl-lsdyna-single`: LS-DYNA Single Job (partition: group6, cpus: 32)
- ✅ `tpl-lsdyna-array`: LS-DYNA Array Job (partition: group6, cpus: 16)

## 🔧 추가 문제 해결

### 문제: 데이터베이스가 비어있음

```bash
# 데이터베이스 초기화 (주의: 기존 데이터 삭제됨)
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory
./reset_database.sh

# 서비스 재시작
./restart_production.sh
```

### 문제: 여전히 Mock 모드로 실행됨

```bash
# Backend 프로세스 환경변수 확인
backend_pid=$(cat backend_5010/.backend.pid)
cat /proc/$backend_pid/environ | tr '\0' '\n' | grep MOCK_MODE

# 만약 MOCK_MODE=true로 보인다면:
# 1. Backend만 재시작
cd backend_5010
./stop.sh
export MOCK_MODE=false
./start.sh

# 2. 로그 확인
tail -20 backend.log
```

### 문제: 템플릿의 Partition이 여전히 잘못됨

데이터베이스에 이미 저장된 템플릿의 partition 수정:

```sql
# SQLite CLI로 수정
sqlite3 backend_5010/database/dashboard.db

-- 기존 잘못된 partition 확인
SELECT id, name, json_extract(config, '$.partition') as partition FROM templates;

-- 'compute'를 'group6'으로 변경
UPDATE templates 
SET config = json_replace(config, '$.partition', 'group6')
WHERE json_extract(config, '$.partition') = 'compute';

-- 확인
SELECT id, name, json_extract(config, '$.partition') as partition FROM templates;

.exit
```

또는 Python 스크립트로:

```python
import sqlite3
import json

conn = sqlite3.connect('backend_5010/database/dashboard.db')
cursor = conn.cursor()

# 모든 템플릿 가져오기
cursor.execute("SELECT id, config FROM templates")
templates = cursor.fetchall()

for tpl_id, config_str in templates:
    config = json.loads(config_str)
    
    # partition 수정
    if config['partition'] in ['compute', 'gpu', 'cpu', 'debug']:
        config['partition'] = 'group6'  # 또는 적절한 그룹
        
        # 업데이트
        cursor.execute(
            "UPDATE templates SET config = ? WHERE id = ?",
            (json.dumps(config), tpl_id)
        )
        print(f"Updated {tpl_id}: partition -> {config['partition']}")

conn.commit()
conn.close()
print("✅ All templates updated")
```

## 📝 체크리스트

재시작 후 확인 사항:

- [ ] Backend 로그에 "PRODUCTION MODE" 표시
- [ ] API 응답의 mode가 "production"
- [ ] Templates가 데이터베이스에서 로드됨
- [ ] Partition 이름이 group1-6로 표시
- [ ] 허용된 CPU 개수가 정책과 일치

## 🎯 예상 결과

성공적으로 적용되면:

```json
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
    {
      "id": "tpl-lsdyna-array",
      "name": "LS-DYNA Array Job",
      "config": {
        "partition": "group6",
        "cpus": 16,
        ...
      }
    }
  ]
}
```

## 🚨 주의사항

1. **데이터베이스 백업**: 초기화 전 항상 백업
   ```bash
   cp backend_5010/database/dashboard.db backend_5010/database/dashboard.db.backup
   ```

2. **사용자 생성 템플릿**: 기존 사용자가 만든 템플릿도 partition 검토 필요

3. **서비스 중단**: 재시작 시 잠깐 서비스 중단됨 (1-2분)

## 📞 문제 지속 시

위 방법으로 해결되지 않으면:

1. 전체 로그 확인
   ```bash
   cat backend_5010/backend.log
   ```

2. 데이터베이스 무결성 확인
   ```bash
   python3 check_db.py
   ```

3. 완전 초기화 (최후의 수단)
   ```bash
   ./stop_all.sh
   rm -rf backend_5010/database/dashboard.db
   rm -rf backend_5010/.backend.pid
   ./start_all.sh
   ```

---

**작성일**: 2025-10-11  
**관련 파일**:
- `restart_production.sh` (신규 생성)
- `backend_5010/templates_api.py`
- `backend_5010/database/schema.sql`
- `backend_5010/start.sh`
