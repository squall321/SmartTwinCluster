# 백엔드 테스트 공통 환경 — 임시 DB·공유 루트를 잡고 블루프린트 모듈 import 전에 env 를 고정한다
import os
import sqlite3
import sys
import tempfile

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

ROOT = tempfile.mkdtemp(prefix='backend_test_')
DB_PATH = os.path.join(ROOT, 'dashboard.db')
JWT_SECRET = 'test-secret'

os.environ.update({
    'SSO_ENABLED': 'true',
    'JWT_SECRET_KEY': JWT_SECRET,
    'DATABASE_PATH': DB_PATH,
    'SHARED_BASE': os.path.join(ROOT, 'shared'),
    'JOB_LOGS_DIR': os.path.join(ROOT, 'shared', 'logs'),
    'JOB_WORK_DIR': os.path.join(ROOT, 'shared', 'jobs'),
    'SINGLE_ROOT': os.path.join(ROOT, 'single'),
    'SLURM_BIN_DIR': os.path.join(ROOT, 'slurm_bin'),
    'KOOCHAINRUN_BIN': os.path.join(ROOT, 'bin', 'KooChainRun'),
})
os.makedirs(os.environ['JOB_LOGS_DIR'], exist_ok=True)


def init_db():
    """job_submissions 를 마이그레이션 SQL 그대로 만든다(이미 있으면 비운다)."""
    conn = sqlite3.connect(DB_PATH)
    conn.execute("CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY, description TEXT)")
    with open(os.path.join(BACKEND_DIR, 'migrations', 'v4.4.1_job_history.sql'), encoding='utf-8') as f:
        conn.executescript(f.read())
    conn.execute("DELETE FROM job_submissions")
    conn.commit()
    conn.close()


def add_submission(job_id, user_id, result_dir, template_id='smarttwin-fullangle-drop', job_name='job'):
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        "INSERT INTO job_submissions (job_id, job_name, template_id, user_id, partition, result_dir) "
        "VALUES (?, ?, ?, ?, '', ?)", (str(job_id), job_name, template_id, user_id, result_dir))
    conn.commit()
    conn.close()


def bearer(username, role='user', permissions=('dashboard',)):
    import jwt
    tok = jwt.encode({'sub': username, 'role': role, 'permissions': list(permissions)}, JWT_SECRET, algorithm='HS256')
    return {'Authorization': f'Bearer {tok}'}
