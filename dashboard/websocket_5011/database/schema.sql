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
-- Sample Data (for Mock Mode)
-- ============================================

-- Sample notifications
INSERT OR IGNORE INTO notifications (id, type, title, message, read, data) VALUES
('notif-001', 'job_completed', 'Job Completed', 'Job #12345 has finished successfully', 0, '{"jobId": "12345", "duration": "2h 30m"}'),
('notif-002', 'job_failed', 'Job Failed', 'Job #12346 failed with exit code 1', 0, '{"jobId": "12346", "exitCode": 1}'),
('notif-003', 'alert', 'High CPU Usage', 'Node compute-001 CPU usage is at 95%', 0, '{"node": "compute-001", "metric": "cpu", "value": 95}'),
('notif-004', 'system', 'Maintenance Scheduled', 'System maintenance on 2025-10-15 from 2-4 AM', 1, '{"date": "2025-10-15", "duration": "2 hours"}'),
('notif-005', 'info', 'New Feature', 'Job templates are now available!', 1, '{"feature": "templates"}');

-- Sample templates
INSERT OR IGNORE INTO templates (id, name, description, category, shared, config, usage_count) VALUES
('tpl-001', 'PyTorch Training', 'Standard PyTorch model training job', 'ml', 1, 
'{"partition": "gpu", "nodes": 1, "cpus": 8, "memory": "32G", "time": "12:00:00", "gpu": 2, "script": "#!/bin/bash\\npython train.py"}', 
45),
('tpl-002', 'TensorFlow Distributed', 'Multi-node TensorFlow training', 'ml', 1,
'{"partition": "gpu", "nodes": 4, "cpus": 16, "memory": "64G", "time": "24:00:00", "gpu": 4, "script": "#!/bin/bash\\npython -m torch.distributed.launch train.py"}',
23),
('tpl-003', 'GROMACS Simulation', 'Molecular dynamics simulation', 'simulation', 1,
'{"partition": "cpu", "nodes": 2, "cpus": 32, "memory": "128G", "time": "48:00:00", "script": "#!/bin/bash\\ngmx mdrun -v -deffnm md"}',
67),
('tpl-004', 'Data Processing', 'Large-scale data processing with Spark', 'data', 1,
'{"partition": "cpu", "nodes": 8, "cpus": 64, "memory": "256G", "time": "06:00:00", "script": "#!/bin/bash\\nspark-submit process.py"}',
34),
('tpl-005', 'Quick Test', 'Quick test job for debugging', 'custom', 0,
'{"partition": "debug", "nodes": 1, "cpus": 1, "memory": "4G", "time": "00:10:00", "script": "#!/bin/bash\necho Hello World"}',
12);

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
