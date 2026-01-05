-- ============================================
-- Migration: v4.5.0_cluster_config
-- Description: Add cluster_config table for cluster group configuration
-- Date: 2025-01-05
-- ============================================

-- Cluster Configuration Table
-- 클러스터 그룹 설정 (파티션, 노드 매핑 등)
CREATE TABLE IF NOT EXISTS cluster_config (
    id INTEGER PRIMARY KEY CHECK(id = 1),  -- 단일 행만 허용
    config TEXT NOT NULL,  -- JSON format for entire cluster configuration
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Notifications Table
CREATE TABLE IF NOT EXISTS notifications (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    title TEXT NOT NULL,
    message TEXT,
    read INTEGER DEFAULT 0,
    data TEXT,  -- JSON format
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Alert Rules Table
CREATE TABLE IF NOT EXISTS alert_rules (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    query TEXT NOT NULL,
    duration TEXT,
    severity TEXT CHECK(severity IN ('info', 'warning', 'critical')) DEFAULT 'warning',
    threshold REAL,
    enabled INTEGER DEFAULT 1,
    annotations TEXT,  -- JSON format
    labels TEXT,  -- JSON format
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- User Preferences Table
CREATE TABLE IF NOT EXISTS user_preferences (
    user_id TEXT PRIMARY KEY,
    theme TEXT DEFAULT 'light',
    dashboard_layout TEXT,  -- JSON format
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Default user preferences (only if not exists)
INSERT OR IGNORE INTO user_preferences (user_id, theme, dashboard_layout)
VALUES ('default', 'light', '{"widgets": []}');

-- Record migration
INSERT OR IGNORE INTO schema_migrations (version, description)
VALUES ('v4.5.0_cluster_config', 'Add cluster_config and related tables');
