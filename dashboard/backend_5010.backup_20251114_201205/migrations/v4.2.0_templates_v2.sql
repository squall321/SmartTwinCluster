-- ============================================
-- Dashboard v4.2.0 Migration
-- Phase 2: Template Management System
-- 작성일: 2025-11-05
-- ============================================

-- ============================================
-- UP Migration: 테이블 생성
-- ============================================

-- Job Templates v2 테이블 (외부 YAML 템플릿 관리)
CREATE TABLE IF NOT EXISTS job_templates_v2 (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    template_id TEXT UNIQUE NOT NULL,        -- 템플릿 고유 ID (YAML의 template.id)
    name TEXT NOT NULL,                      -- 템플릿 이름 (파일명 기반)
    display_name TEXT NOT NULL,              -- 표시 이름 (한글 가능)
    description TEXT,                        -- 템플릿 설명
    category TEXT NOT NULL,                  -- 카테고리 (ml, cfd, structural 등)
    tags TEXT,                               -- JSON: 태그 배열 ["gpu", "mpi"]
    version TEXT DEFAULT '1.0.0',            -- 템플릿 버전
    author TEXT DEFAULT 'unknown',           -- 작성자
    is_public BOOLEAN DEFAULT 0,             -- 공개 여부
    source TEXT,                             -- 소스 (official, community, private:user)

    -- Slurm 설정 (JSON)
    slurm_config TEXT,                       -- JSON: partition, nodes, cpus, mem, time, gres 등

    -- Apptainer 설정 (JSON)
    apptainer_config TEXT,                   -- JSON: image_name, app, bind 등
    apptainer_image_id TEXT,                 -- Apptainer 이미지 ID (FK, nullable)

    -- 파일 스키마 (JSON)
    file_schema TEXT,                        -- JSON: input_schema, config_schema, output_pattern

    -- 스크립트 템플릿 (JSON)
    script_template TEXT,                    -- JSON: pre_exec, main_exec, post_exec

    -- 파일 메타데이터
    file_path TEXT,                          -- YAML 파일 경로
    file_hash TEXT,                          -- 파일 해시 (변경 감지용)

    -- 타임스탬프
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_synced DATETIME,                    -- 마지막 동기화 시각

    -- 상태
    is_active BOOLEAN DEFAULT 1,             -- 활성 상태

    -- FK (optional)
    FOREIGN KEY (apptainer_image_id) REFERENCES apptainer_images(id) ON DELETE SET NULL
);

-- 인덱스 생성
CREATE INDEX IF NOT EXISTS idx_templates_v2_template_id ON job_templates_v2(template_id);
CREATE INDEX IF NOT EXISTS idx_templates_v2_category ON job_templates_v2(category);
CREATE INDEX IF NOT EXISTS idx_templates_v2_tags ON job_templates_v2(tags);
CREATE INDEX IF NOT EXISTS idx_templates_v2_public ON job_templates_v2(is_public);
CREATE INDEX IF NOT EXISTS idx_templates_v2_source ON job_templates_v2(source);
CREATE INDEX IF NOT EXISTS idx_templates_v2_active ON job_templates_v2(is_active);
CREATE INDEX IF NOT EXISTS idx_templates_v2_author ON job_templates_v2(author);

-- ============================================
-- 샘플 데이터 (개발/테스트용)
-- 실제 데이터는 /shared/templates/ 스캔으로 생성됨
-- ============================================

-- PyTorch Training Template
INSERT OR IGNORE INTO job_templates_v2 (
    template_id, name, display_name, description, category, tags,
    version, author, is_public, source,
    slurm_config, apptainer_config, file_schema, script_template,
    file_path, file_hash, created_at, updated_at, is_active
) VALUES (
    'pytorch-training-v1',
    'pytorch_training',
    'PyTorch 모델 학습',
    'PyTorch를 이용한 딥러닝 모델 학습 템플릿',
    'ml',
    '["gpu", "pytorch", "ml", "deep-learning"]',
    '1.0.0',
    'admin',
    1,
    'official',
    '{"partition": "compute", "nodes": 1, "ntasks": 1, "cpus_per_task": 8, "mem": "32G", "time": "04:00:00", "gres": "gpu:1"}',
    '{"image_name": "KooSimulationPython313.sif", "app": "python", "bind": ["/shared/datasets:/datasets:ro", "/shared/models:/models:rw"]}',
    '{"input_schema": {"required": [{"name": "training_script", "pattern": "*.py", "type": "code", "max_size": "10MB"}]}}',
    '{"pre_exec": "#!/bin/bash\\nmkdir -p data\\ntar -xzf dataset.tar.gz -C data", "main_exec": "#!/bin/bash\\napptainer exec --nv $APPTAINER_IMAGE python training_script.py"}',
    '/shared/templates/official/ml/pytorch_training.yaml',
    'abc123',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    1
);

-- OpenFOAM CFD Template
INSERT OR IGNORE INTO job_templates_v2 (
    template_id, name, display_name, description, category, tags,
    version, author, is_public, source,
    slurm_config, apptainer_config, file_schema, script_template,
    file_path, file_hash, created_at, updated_at, is_active
) VALUES (
    'openfoam-cfd-v1',
    'openfoam_simulation',
    'OpenFOAM CFD 시뮬레이션',
    'OpenFOAM을 이용한 유체역학 시뮬레이션',
    'cfd',
    '["cfd", "openfoam", "fluid-dynamics", "mpi"]',
    '1.0.0',
    'admin',
    1,
    'official',
    '{"partition": "compute", "nodes": 2, "ntasks": 32, "cpus_per_task": 1, "mem": "64G", "time": "12:00:00"}',
    '{"image_name": "openfoam_v2312.sif", "app": "simpleFoam", "bind": ["/shared/cfd_cases:/cases:ro"]}',
    '{"input_schema": {"required": [{"name": "case_directory", "pattern": "*/", "type": "directory", "max_size": "5GB"}]}}',
    '{"pre_exec": "#!/bin/bash\\ncp -r case_directory case\\ncd case\\napptainer exec $APPTAINER_IMAGE blockMesh", "main_exec": "#!/bin/bash\\nmpirun -np $SLURM_NTASKS apptainer exec $APPTAINER_IMAGE simpleFoam -parallel"}',
    '/shared/templates/official/cfd/openfoam_simulation.yaml',
    'def456',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    1
);

-- GROMACS Molecular Dynamics Template
INSERT OR IGNORE INTO job_templates_v2 (
    template_id, name, display_name, description, category, tags,
    version, author, is_public, source,
    slurm_config, apptainer_config, file_schema, script_template,
    file_path, file_hash, created_at, updated_at, is_active
) VALUES (
    'gromacs-md-v1',
    'gromacs_simulation',
    'GROMACS 분자동역학',
    'GROMACS를 이용한 분자동역학 시뮬레이션',
    'molecular',
    '["molecular-dynamics", "gromacs", "protein", "gpu"]',
    '1.0.0',
    'admin',
    1,
    'official',
    '{"partition": "compute", "nodes": 1, "ntasks": 8, "cpus_per_task": 1, "mem": "32G", "time": "24:00:00", "gres": "gpu:1"}',
    '{"image_name": "gromacs_gpu.sif", "bind": ["/shared/proteins:/proteins:ro"]}',
    '{"input_schema": {"required": [{"name": "structure_file", "pattern": "*.pdb", "type": "data", "max_size": "100MB"}]}}',
    '{"pre_exec": "#!/bin/bash\\nmkdir -p trajectory\\napptainer exec $APPTAINER_IMAGE gmx pdb2gmx -f structure_file.pdb", "main_exec": "#!/bin/bash\\napptainer exec --nv $APPTAINER_IMAGE gmx mdrun -v -deffnm md -nb gpu"}',
    '/shared/templates/official/molecular/gromacs_simulation.yaml',
    'ghi789',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    1
);

-- ============================================
-- DOWN Migration: 롤백 (테이블 삭제)
-- ============================================

-- 롤백 시 실행할 SQL
-- DROP TABLE IF EXISTS job_templates_v2;

-- ============================================
-- 마이그레이션 버전 기록
-- ============================================

-- 현재 마이그레이션 버전 기록
INSERT OR IGNORE INTO schema_migrations (version, description)
VALUES ('v4.2.0', 'Phase 2: Template Management System - job_templates_v2 table');

-- ============================================
-- 마이그레이션 완료
-- ============================================
