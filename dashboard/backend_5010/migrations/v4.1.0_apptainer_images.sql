-- ============================================
-- Dashboard v4.1.0 Migration
-- Phase 1: Apptainer Discovery & Integration
-- 작성일: 2025-11-05
-- ============================================

-- ============================================
-- UP Migration: 테이블 생성
-- ============================================

-- Apptainer 이미지 메타데이터 테이블
CREATE TABLE IF NOT EXISTS apptainer_images (
    id TEXT PRIMARY KEY,                      -- UUID 또는 해시 기반 ID
    name TEXT NOT NULL,                       -- 파일명 (예: vnc_gnome.sif)
    path TEXT NOT NULL,                       -- 전체 경로 (예: /opt/apptainers/vnc_gnome.sif)
    node TEXT NOT NULL,                       -- 노드 호스트명 (예: viz-node001)
    partition TEXT,                           -- 파티션 (viz, compute)
    type TEXT CHECK(type IN ('viz', 'compute', 'custom')),  -- 이미지 타입
    size INTEGER,                             -- 파일 크기 (bytes)
    version TEXT,                             -- 이미지 버전 (예: 1.0.0)
    description TEXT,                         -- 이미지 설명
    labels TEXT,                              -- JSON: 이미지 라벨 {"gpu": "required", "mpi": "true"}
    apps TEXT,                                -- JSON: 내부 앱 목록 ["python", "jupyter", "gedit"]
    runscript TEXT,                           -- 기본 runscript 내용
    env_vars TEXT,                            -- JSON: 환경 변수 {"PATH": "/usr/local/bin:..."}
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,  -- 레코드 생성 시각
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,  -- 레코드 업데이트 시각
    last_scanned DATETIME,                    -- 마지막 스캔 시각
    is_active BOOLEAN DEFAULT 1               -- 활성 상태 (1: 활성, 0: 비활성)
);

-- 인덱스 생성 (검색 성능 향상)
CREATE INDEX IF NOT EXISTS idx_images_node ON apptainer_images(node);
CREATE INDEX IF NOT EXISTS idx_images_partition ON apptainer_images(partition);
CREATE INDEX IF NOT EXISTS idx_images_type ON apptainer_images(type);
CREATE INDEX IF NOT EXISTS idx_images_active ON apptainer_images(is_active);
CREATE INDEX IF NOT EXISTS idx_images_name ON apptainer_images(name);

-- 복합 인덱스 (partition + type 조합 검색 최적화)
CREATE INDEX IF NOT EXISTS idx_images_partition_type ON apptainer_images(partition, type);

-- UNIQUE 제약 (동일 노드의 동일 경로는 중복 불가)
CREATE UNIQUE INDEX IF NOT EXISTS idx_images_node_path ON apptainer_images(node, path);

-- ============================================
-- 샘플 데이터 (개발/테스트용)
-- 프로덕션에서는 실제 스캔으로 데이터 생성
-- ============================================

-- Viz Node 이미지 예시
INSERT OR IGNORE INTO apptainer_images (
    id, name, path, node, partition, type, size, version, description,
    labels, apps, runscript, env_vars, created_at, updated_at, last_scanned, is_active
) VALUES (
    'viz001',
    'vnc_gnome.sif',
    '/opt/apptainers/vnc_gnome.sif',
    'viz-node001',
    'viz',
    'viz',
    2147483648,
    '1.0.0',
    'VNC server with GNOME desktop environment',
    '{"display": "required", "gpu": "optional", "vnc": "true"}',
    '["vncserver", "gnome-session", "firefox", "gedit"]',
    '#!/bin/bash\nvncserver :1\n',
    '{"DISPLAY": ":1", "PATH": "/usr/local/bin:/usr/bin"}',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    1
);

INSERT OR IGNORE INTO apptainer_images (
    id, name, path, node, partition, type, size, version, description,
    labels, apps, runscript, env_vars, created_at, updated_at, last_scanned, is_active
) VALUES (
    'viz002',
    'vnc_gnome_lsprepost.sif',
    '/opt/apptainers/vnc_gnome_lsprepost.sif',
    'viz-node001',
    'viz',
    'viz',
    3221225472,
    '1.0.0',
    'VNC with GNOME and LS-PrePost for FEA visualization',
    '{"display": "required", "gpu": "required", "vnc": "true", "fea": "true"}',
    '["vncserver", "gnome-session", "lsprepost", "paraview"]',
    '#!/bin/bash\nvncserver :1\n',
    '{"DISPLAY": ":1", "PATH": "/usr/local/bin:/usr/bin"}',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    1
);

-- Compute Node 이미지 예시
INSERT OR IGNORE INTO apptainer_images (
    id, name, path, node, partition, type, size, version, description,
    labels, apps, runscript, env_vars, created_at, updated_at, last_scanned, is_active
) VALUES (
    'compute001',
    'KooSimulationPython313.sif',
    '/opt/apptainers/KooSimulationPython313.sif',
    'compute-node001',
    'compute',
    'compute',
    1073741824,
    '3.13.0',
    'Python 3.13 environment for scientific computing and simulation',
    '{"python": "3.13", "mpi": "true", "gpu": "optional"}',
    '["python", "python3", "pip", "jupyter", "numpy", "scipy"]',
    '#!/bin/bash\npython "$@"\n',
    '{"PATH": "/opt/python3.13/bin:/usr/local/bin:/usr/bin", "PYTHONPATH": "/opt/python3.13/lib"}',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    1
);

INSERT OR IGNORE INTO apptainer_images (
    id, name, path, node, partition, type, size, version, description,
    labels, apps, runscript, env_vars, created_at, updated_at, last_scanned, is_active
) VALUES (
    'compute002',
    'openfoam_v2312.sif',
    '/opt/apptainers/openfoam_v2312.sif',
    'compute-node001',
    'compute',
    'compute',
    4294967296,
    '2312',
    'OpenFOAM v2312 for CFD simulations',
    '{"cfd": "true", "mpi": "true", "openfoam": "2312"}',
    '["simpleFoam", "icoFoam", "paraFoam", "blockMesh"]',
    '#!/bin/bash\nsource /opt/openfoam2312/etc/bashrc\n"$@"\n',
    '{"PATH": "/opt/openfoam2312/bin:/usr/local/bin", "WM_PROJECT_VERSION": "2312"}',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    1
);

-- ============================================
-- DOWN Migration: 롤백 (테이블 삭제)
-- ============================================

-- 롤백 시 실행할 SQL
-- DROP TABLE IF EXISTS apptainer_images;

-- ============================================
-- 마이그레이션 버전 기록
-- ============================================

-- 마이그레이션 이력 테이블 (없으면 생성)
CREATE TABLE IF NOT EXISTS schema_migrations (
    version TEXT PRIMARY KEY,
    applied_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    description TEXT
);

-- 현재 마이그레이션 버전 기록
INSERT OR IGNORE INTO schema_migrations (version, description)
VALUES ('v4.1.0', 'Phase 1: Apptainer Discovery & Integration - apptainer_images table');

-- ============================================
-- 마이그레이션 완료
-- ============================================
