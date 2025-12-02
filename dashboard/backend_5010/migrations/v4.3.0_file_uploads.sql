-- ============================================
-- v4.3.0: Unified File Upload System
-- 작성일: 2025-11-05
-- 설명: 대용량 파일 업로드 및 청크 관리
-- ============================================

-- file_uploads 테이블 생성
CREATE TABLE IF NOT EXISTS file_uploads (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    upload_id TEXT NOT NULL UNIQUE,           -- 고유 업로드 ID
    filename TEXT NOT NULL,                   -- 파일명
    file_size INTEGER NOT NULL,               -- 파일 크기 (bytes)
    file_type TEXT NOT NULL,                  -- 파일 타입 (data, config, script, etc.)

    -- 사용자 및 작업 정보
    user_id TEXT NOT NULL,                    -- 사용자 ID
    job_id TEXT,                              -- 작업 ID (선택)

    -- 저장 정보
    storage_path TEXT NOT NULL,               -- 저장 디렉토리 경로
    file_path TEXT,                           -- 최종 파일 경로 (완료 후)

    -- 청크 정보
    chunk_size INTEGER NOT NULL,              -- 청크 크기 (bytes)
    total_chunks INTEGER NOT NULL,            -- 총 청크 수
    uploaded_chunks INTEGER DEFAULT 0,        -- 업로드된 청크 수

    -- 상태 정보
    status TEXT NOT NULL DEFAULT 'initialized',  -- initialized, uploading, completed, cancelled, failed
    error_message TEXT,                       -- 에러 메시지 (실패 시)

    -- 타임스탬프
    created_at TEXT NOT NULL,                 -- 생성 시각
    updated_at TEXT,                          -- 수정 시각
    completed_at TEXT,                        -- 완료 시각

    -- 인덱스
    FOREIGN KEY (job_id) REFERENCES jobs(id) ON DELETE CASCADE
);

-- 인덱스 생성
CREATE INDEX IF NOT EXISTS idx_file_uploads_user_id ON file_uploads(user_id);
CREATE INDEX IF NOT EXISTS idx_file_uploads_job_id ON file_uploads(job_id);
CREATE INDEX IF NOT EXISTS idx_file_uploads_status ON file_uploads(status);
CREATE INDEX IF NOT EXISTS idx_file_uploads_created_at ON file_uploads(created_at);

-- 뷰: 진행 중인 업로드 목록
CREATE VIEW IF NOT EXISTS v_active_uploads AS
SELECT
    upload_id,
    filename,
    file_size,
    file_type,
    user_id,
    job_id,
    status,
    uploaded_chunks,
    total_chunks,
    ROUND((uploaded_chunks * 100.0 / total_chunks), 2) AS progress_percent,
    created_at,
    updated_at
FROM file_uploads
WHERE status IN ('initialized', 'uploading')
ORDER BY created_at DESC;

-- 뷰: 완료된 업로드 통계
CREATE VIEW IF NOT EXISTS v_upload_stats AS
SELECT
    user_id,
    COUNT(*) AS total_uploads,
    SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed_uploads,
    SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed_uploads,
    SUM(CASE WHEN status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled_uploads,
    SUM(file_size) AS total_bytes_uploaded,
    AVG(file_size) AS avg_file_size
FROM file_uploads
GROUP BY user_id;

-- 업로드 세션 자동 정리 트리거 (30일 이상 된 취소/실패 업로드)
CREATE TRIGGER IF NOT EXISTS cleanup_old_uploads
AFTER INSERT ON file_uploads
BEGIN
    DELETE FROM file_uploads
    WHERE status IN ('cancelled', 'failed')
    AND created_at < datetime('now', '-30 days');
END;
