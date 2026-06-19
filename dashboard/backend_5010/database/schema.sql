-- Dashboard Database Schema
-- SQLite 3.x
-- Created: 2025-10-07

-- ============================================
-- Notifications Table
-- ============================================
CREATE TABLE IF NOT EXISTS notifications (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL CHECK(type IN ('job_completed', 'job_failed', 'job_started', 'alert', 'system', 'info')),
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    data TEXT,  -- JSON format for additional data
    read BOOLEAN DEFAULT 0,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_notifications_read ON notifications(read);
CREATE INDEX IF NOT EXISTS idx_notifications_timestamp ON notifications(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_type ON notifications(type);

-- ============================================
-- Job Templates Table
-- ============================================
CREATE TABLE IF NOT EXISTS templates (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    category TEXT CHECK(category IN ('ml', 'simulation', 'data', 'custom')) DEFAULT 'custom',
    shared BOOLEAN DEFAULT 0,
    config TEXT NOT NULL,  -- JSON format for job configuration
    created_by TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    usage_count INTEGER DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_templates_category ON templates(category);
CREATE INDEX IF NOT EXISTS idx_templates_shared ON templates(shared);
CREATE INDEX IF NOT EXISTS idx_templates_usage ON templates(usage_count DESC);

-- ============================================
-- Alert Rules Table (for Prometheus)
-- ============================================
CREATE TABLE IF NOT EXISTS alert_rules (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    query TEXT NOT NULL,
    duration TEXT DEFAULT '5m',
    severity TEXT CHECK(severity IN ('critical', 'warning', 'info')) DEFAULT 'warning',
    threshold REAL,
    enabled BOOLEAN DEFAULT 1,
    annotations TEXT,  -- JSON format
    labels TEXT,  -- JSON format
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_alert_rules_enabled ON alert_rules(enabled);
CREATE INDEX IF NOT EXISTS idx_alert_rules_severity ON alert_rules(severity);

-- ============================================
-- Retry Policies Table (for Job Auto-retry)
-- ============================================
CREATE TABLE IF NOT EXISTS retry_policies (
    job_id TEXT PRIMARY KEY,
    max_retries INTEGER DEFAULT 3,
    current_retries INTEGER DEFAULT 0,
    retry_on_codes TEXT,  -- JSON array format, e.g., "[1,2,3]"
    enabled BOOLEAN DEFAULT 1,
    last_retry_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_retry_policies_enabled ON retry_policies(enabled);

-- ============================================
-- User Preferences Table (for Custom Dashboard)
-- ============================================
CREATE TABLE IF NOT EXISTS user_preferences (
    user_id TEXT PRIMARY KEY,
    dashboard_layout TEXT,  -- JSON format for widget positions
    theme TEXT CHECK(theme IN ('light', 'dark')) DEFAULT 'light',
    notifications_enabled BOOLEAN DEFAULT 1,
    email_notifications BOOLEAN DEFAULT 0,
    preferences TEXT,  -- JSON format for additional preferences
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- Cluster Configuration Table
-- 🆕 클러스터 그룹 구성 저장
-- ============================================
CREATE TABLE IF NOT EXISTS cluster_config (
    id INTEGER PRIMARY KEY CHECK(id = 1),  -- 단일 행만 허용
    config TEXT NOT NULL,  -- JSON format for entire cluster configuration
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- Apptainer Images Table
-- 🆕 Apptainer 이미지 레지스트리
-- ============================================
CREATE TABLE IF NOT EXISTS apptainer_images (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    path TEXT NOT NULL,
    node TEXT DEFAULT 'headnode',
    partition TEXT CHECK(partition IN ('compute', 'viz', 'shared')) NOT NULL,
    type TEXT CHECK(type IN ('viz', 'compute', 'shared', 'custom')) DEFAULT 'custom',
    size INTEGER DEFAULT 0,
    version TEXT DEFAULT '1.0.0',
    description TEXT,
    labels TEXT,  -- JSON format
    apps TEXT,  -- JSON array format
    runscript TEXT,
    env_vars TEXT,  -- JSON format
    command_templates TEXT,  -- JSON format: 명령어 템플릿 배열
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_scanned DATETIME DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_apptainer_partition ON apptainer_images(partition);
CREATE INDEX IF NOT EXISTS idx_apptainer_type ON apptainer_images(type);
CREATE INDEX IF NOT EXISTS idx_apptainer_active ON apptainer_images(is_active);
CREATE INDEX IF NOT EXISTS idx_apptainer_node ON apptainer_images(node);

-- Sample Data (for Production Mode)

-- Sample notifications
INSERT OR IGNORE INTO notifications (id, type, title, message, read, data) VALUES
('notif-001', 'job_completed', 'Job Completed', 'Job #12345 has finished successfully', 0, '{"jobId": "12345", "duration": "2h 30m"}'),
('notif-002', 'job_failed', 'Job Failed', 'Job #12346 failed with exit code 1', 0, '{"jobId": "12346", "exitCode": 1}'),
('notif-003', 'alert', 'High CPU Usage', 'Node compute-001 CPU usage is at 95%', 0, '{"node": "compute-001", "metric": "cpu", "value": 95}'),
('notif-004', 'system', 'Maintenance Scheduled', 'System maintenance on 2025-10-15 from 2-4 AM', 1, '{"date": "2025-10-15", "duration": "2 hours"}'),
('notif-005', 'info', 'New Feature', 'Job templates are now available!', 1, '{"feature": "templates"}');

-- Production Templates: LS-DYNA Only (Fixed JSON)
INSERT OR IGNORE INTO templates (id, name, description, category, shared, config, usage_count) VALUES
('tpl-lsdyna-single', 
 'LS-DYNA Single Job', 
 'LS-DYNA simulation with single K-file input. Upload one K file and it will be automatically configured for MPP solver.', 
 'simulation', 
 1, 
 '{"partition": "group6", "nodes": 1, "cpus": 32, "memory": "64GB", "time": "24:00:00", "script": "#!/bin/bash\n#SBATCH --ntasks=32\n\nmodule load lsdyna/R13.1.0\n\nNPROCS=32\nMEMORY=64000000\n\necho \"LS-DYNA Single Job\"\necho \"Job ID: $SLURM_JOB_ID\"\necho \"Node: $SLURM_NODELIST\"\necho \"Cores: $NPROCS\"\n\nif [ ! -f \"$K_FILE\" ]; then\n    echo \"Error: K file not found: $K_FILE\"\n    exit 1\nfi\n\nOUTPUT_DIR=$(dirname $K_FILE)/output\nmkdir -p $OUTPUT_DIR\ncd $OUTPUT_DIR\n\nmpirun -np $NPROCS ls-dyna_mpp I=$K_FILE MEMORY=$MEMORY NCPU=$NPROCS\n\nEXIT_CODE=$?\nif [ $EXIT_CODE -eq 0 ]; then\n    echo \"LS-DYNA simulation completed successfully\"\nelse\n    echo \"LS-DYNA simulation failed with exit code $EXIT_CODE\"\nfi\nexit $EXIT_CODE"}', 
 15),
('tpl-lsdyna-array', 
 'LS-DYNA Array Job', 
 'LS-DYNA array job for multiple K-files. Upload multiple K files and each will be run as a separate job with dedicated resources and output directory.', 
 'simulation', 
 1,
 '{"partition": "group6", "nodes": 1, "cpus": 16, "memory": "32GB", "time": "12:00:00", "script": "#!/bin/bash\n#SBATCH --ntasks=16\n\nmodule load lsdyna/R13.1.0\n\nNPROCS=16\nMEMORY=32000000\n\necho \"LS-DYNA Array Job Submission\"\necho \"Parent Job ID: $SLURM_JOB_ID\"\necho \"Total K files: ${#K_FILES[@]}\"\n\nfor K_FILE in \"${K_FILES[@]}\"; do\n    if [ ! -f \"$K_FILE\" ]; then\n        echo \"Error: K file not found: $K_FILE\"\n        exit 1\n    fi\ndone\n\nJOB_IDS=()\nfor i in \"${!K_FILES[@]}\"; do\n    K_FILE=\"${K_FILES[$i]}\"\n    BASENAME=$(basename \"$K_FILE\" .k)\n    \n    echo \"[$((i+1))/${#K_FILES[@]}] Submitting job for: $BASENAME\"\n    \n    JOB_DIR=\"/Data/Results/lsdyna_${SLURM_JOB_ID}_${i}_${BASENAME}\"\n    mkdir -p $JOB_DIR/output\n    \n    SUBMITTED_JOB_ID=$(sbatch --parsable $JOB_DIR/run_lsdyna.sh)\n    JOB_IDS+=($SUBMITTED_JOB_ID)\n    \n    echo \"Job ID: $SUBMITTED_JOB_ID\"\n    sleep 1\ndone\n\necho \"Total jobs submitted: ${#JOB_IDS[@]}\"\necho \"Job IDs: ${JOB_IDS[@]}\""}',
 8);

-- Sample alert rules
INSERT OR IGNORE INTO alert_rules (id, name, query, duration, severity, threshold, enabled, annotations, labels) VALUES
('rule-001', 'High CPU Usage', 'node_cpu_usage > 90', '5m', 'warning', 90, 1,
'{"summary": "CPU usage is above 90%", "description": "Node CPU usage is high"}',
'{"team": "ops", "severity": "warning"}'),
('rule-002', 'High Memory Usage', 'node_memory_usage > 85', '10m', 'warning', 85, 1,
'{"summary": "Memory usage is above 85%", "description": "Node memory usage is high"}',
'{"team": "ops", "severity": "warning"}'),
('rule-003', 'Node Down', 'up == 0', '1m', 'critical', 0, 1,
'{"summary": "Node is down", "description": "Node is not responding"}',
'{"team": "ops", "severity": "critical"}'),
('rule-004', 'Disk Almost Full', 'node_disk_usage > 90', '15m', 'critical', 90, 1,
'{"summary": "Disk usage is above 90%", "description": "Node disk usage is high"}',
'{"team": "ops", "severity": "critical"}');

-- Default user preferences
INSERT OR IGNORE INTO user_preferences (user_id, theme, dashboard_layout) VALUES
('default', 'light', '{"widgets": []}');

-- Default cluster configuration
-- 초기 클러스터 그룹 구성 (initialData.ts와 일치)
INSERT OR IGNORE INTO cluster_config (id, config) VALUES
(1, '{"groups": [{"id": 1, "name": "Group 1", "partitionName": "group1", "qosName": "group1_qos", "allowedCoreSizes": [8192], "color": "#3b82f6", "description": "Large scale jobs", "nodeCount": 64, "totalCores": 8192, "nodes": []}, {"id": 2, "name": "Group 2", "partitionName": "group2", "qosName": "group2_qos", "allowedCoreSizes": [1024], "color": "#10b981", "description": "Medium jobs", "nodeCount": 64, "totalCores": 8192, "nodes": []}, {"id": 3, "name": "Group 3", "partitionName": "group3", "qosName": "group3_qos", "allowedCoreSizes": [1024], "color": "#f59e0b", "description": "Medium jobs", "nodeCount": 64, "totalCores": 8192, "nodes": []}, {"id": 4, "name": "Group 4", "partitionName": "group4", "qosName": "group4_qos", "allowedCoreSizes": [128], "color": "#ef4444", "description": "Small jobs", "nodeCount": 100, "totalCores": 12800, "nodes": []}, {"id": 5, "name": "Group 5", "partitionName": "group5", "qosName": "group5_qos", "allowedCoreSizes": [128], "color": "#8b5cf6", "description": "Small jobs", "nodeCount": 14, "totalCores": 1792, "nodes": []}, {"id": 6, "name": "Group 6", "partitionName": "group6", "qosName": "group6_qos", "allowedCoreSizes": [8, 16, 32, 64], "color": "#ec4899", "description": "Flexible jobs", "nodeCount": 64, "totalCores": 8192, "nodes": []}], "totalNodes": 370, "totalCores": 47360, "clusterName": "HPC-Cluster-370", "controllerIp": "192.168.1.10"}');

-- ============================================================================
-- 감사 로그 (변경계 Slurm 관리 작업 추적: 노드 drain/down, 파티션 state, 잡 cancel 등)
-- ============================================================================
CREATE TABLE IF NOT EXISTS audit_log (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp   DATETIME DEFAULT CURRENT_TIMESTAMP,
    username    TEXT,
    action      TEXT NOT NULL,   -- 점 표기: node.drain, partition.update, job.cancel 등
    target      TEXT,            -- 노드명 / 파티션명 / 잡ID
    detail      TEXT,            -- JSON: reason, command 등
    result      TEXT DEFAULT 'success',
    source_ip   TEXT
);
CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_log(timestamp);
CREATE INDEX IF NOT EXISTS idx_audit_username ON audit_log(username);
CREATE INDEX IF NOT EXISTS idx_audit_action ON audit_log(action);

-- ============================================================================
-- 개인 액세스 토큰 (MCP 등 외부 클라이언트용 — Claude Code/Desktop 연동)
-- 평문은 발급 시 1회만 노출, DB 엔 sha256 해시만. users 테이블이 없어 신원 스냅샷 저장.
-- ============================================================================
CREATE TABLE IF NOT EXISTS personal_access_tokens (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    username         TEXT NOT NULL,
    name             TEXT NOT NULL,             -- 토큰 라벨(예: 내 노트북)
    token_prefix     TEXT NOT NULL,             -- 표시용(kst_ + 앞 8자)
    token_hash       TEXT NOT NULL UNIQUE,      -- sha256(평문)
    email            TEXT,                       -- 발급 시점 신원 스냅샷
    groups_json      TEXT,                       -- JSON array
    permissions_json TEXT,                       -- JSON array
    role             TEXT,                       -- admin/poweruser/user
    created_at       DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_used_at     DATETIME,
    expires_at       DATETIME,
    revoked_at       DATETIME
);
CREATE INDEX IF NOT EXISTS idx_pat_username ON personal_access_tokens(username);
CREATE UNIQUE INDEX IF NOT EXISTS idx_pat_token_hash ON personal_access_tokens(token_hash);
