-- ============================================
-- Dashboard v4.4.1 Migration
-- Job Submission History
-- 작성일: 2025-11-14
-- ============================================

-- Job 제출 이력 테이블
CREATE TABLE IF NOT EXISTS job_submissions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Job 정보
    job_id TEXT NOT NULL,                      -- Slurm Job ID
    job_name TEXT NOT NULL,                    -- Job 이름

    -- Template 정보
    template_id TEXT NOT NULL,                 -- Template ID
    template_name TEXT,                        -- Template 이름
    template_version TEXT,                     -- Template 버전

    -- 사용자 정보
    user_id TEXT NOT NULL,                     -- 제출한 사용자
    username TEXT,                             -- 사용자 이름

    -- Slurm 설정
    partition TEXT NOT NULL,                   -- 파티션
    nodes INTEGER,                             -- 노드 수
    cpus INTEGER,                              -- CPU 수
    memory TEXT,                               -- 메모리
    time_limit TEXT,                           -- 시간 제한

    -- Apptainer 정보
    apptainer_image TEXT,                      -- 사용된 이미지

    -- 파일 정보 (JSON)
    uploaded_files TEXT,                       -- {"geometry": {...}, "config": {...}}

    -- 스크립트 정보
    script_path TEXT,                          -- 생성된 스크립트 경로
    script_hash TEXT,                          -- 스크립트 해시 (변조 감지)

    -- 상태 추적
    status TEXT DEFAULT 'submitted',           -- submitted, running, completed, failed, cancelled
    slurm_state TEXT,                          -- Slurm 상태 (PD, R, CG, CD, F, CA 등)
    exit_code INTEGER,                         -- 종료 코드

    -- 타임스탬프
    submitted_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    started_at DATETIME,
    completed_at DATETIME,

    -- 결과 정보
    result_dir TEXT,                           -- 결과 디렉토리
    output_files TEXT,                         -- 출력 파일 목록 (JSON)
    error_message TEXT,                        -- 에러 메시지

    -- 통계
    cpu_time INTEGER,                          -- CPU 시간 (초)
    wall_time INTEGER,                         -- 실제 소요 시간 (초)
    memory_used TEXT                           -- 사용된 메모리
);

-- 인덱스 생성
CREATE INDEX IF NOT EXISTS idx_job_submissions_job_id ON job_submissions(job_id);
CREATE INDEX IF NOT EXISTS idx_job_submissions_user_id ON job_submissions(user_id);
CREATE INDEX IF NOT EXISTS idx_job_submissions_template_id ON job_submissions(template_id);
CREATE INDEX IF NOT EXISTS idx_job_submissions_status ON job_submissions(status);
CREATE INDEX IF NOT EXISTS idx_job_submissions_submitted_at ON job_submissions(submitted_at DESC);

-- 마이그레이션 버전 기록
INSERT OR IGNORE INTO schema_migrations (version, description)
VALUES ('v4.4.1', 'Job Submission History Table');

-- ============================================
-- 마이그레이션 완료
-- ============================================
