# 끝난 잡에 후처리 잡을 거는 POST /api/jobs/<id>/postprocess 회귀 테스트 — sbatch·squeue·KooChainRun 은 대역
import json
import os
import sqlite3
import subprocess
import unittest

import _env  # noqa: F401
from flask import Flask

import job_logs_api
import job_submit_api

SLURM_BIN = os.environ['SLURM_BIN_DIR']
SQUEUE_OUT = os.path.join(_env.ROOT, 'squeue_out')
SBATCH_RC = os.path.join(_env.ROOT, 'sbatch_rc')
LAST_SCRIPT = os.path.join(_env.ROOT, 'last_sbatch.sh')


def _stub(path, body):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(f'#!/bin/bash\n{body}\n')
    os.chmod(path, 0o755)


class PostprocessRouteTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        _stub(os.path.join(SLURM_BIN, 'squeue'), f'cat {SQUEUE_OUT} 2>/dev/null; exit 0')
        _stub(os.path.join(SLURM_BIN, 'sbatch'),
              f'rc=$(cat {SBATCH_RC} 2>/dev/null || echo 0); [ "$rc" = 0 ] || {{ echo "sbatch: error: nope" >&2; exit 1; }}\n'
              f'cp "$1" {LAST_SCRIPT}; echo "Submitted batch job 5001"')
        # 후처리 잡 안의 KooChainRun 대역 — postprocess 면 종합 리포트를 만든다
        _stub(os.environ['KOOCHAINRUN_BIN'],
              'echo "kcr $*"; [ "$1" = postprocess ] && echo "<html/>" > output/sphere_report.html; exit 0')
        app = Flask(__name__)
        app.register_blueprint(job_submit_api.job_submit_bp)
        app.register_blueprint(job_logs_api.job_logs_bp)
        cls.client = app.test_client()

    def setUp(self):
        _env.init_db()
        for p in (SQUEUE_OUT, SBATCH_RC, LAST_SCRIPT):
            if os.path.exists(p):
                os.remove(p)
        self.rd = os.path.join(_env.ROOT, 'single', 'alice', 'drop_300')
        os.makedirs(os.path.join(self.rd, 'output'), exist_ok=True)
        with open(os.path.join(self.rd, 'runner_config.json'), 'w') as f:
            json.dump({'postprocess': {'enabled': True}}, f)
        self.manifest = os.path.join(self.rd, 'output', 'return_manifest.json')
        with open(self.manifest, 'w') as f:
            json.dump({'ok': False, 'stage': 'complete'}, f)
        for name in ('sphere_report.html', 'return_manifest.prev.json'):
            p = os.path.join(self.rd, 'output', name)
            if os.path.exists(p):
                os.remove(p)
        _env.add_submission('300', 'alice', self.rd, job_name='drop')
        _env.add_submission('302', 'alice', self.rd, template_id='legacy-script')

    def post(self, job_id, body=None, user='alice', role='user'):
        return self.client.post(f'/api/jobs/{job_id}/postprocess', json=body or {},
                                headers=_env.bearer(user, role=role))

    def test_no_token_401(self):
        self.assertEqual(self.client.post('/api/jobs/300/postprocess', json={}).status_code, 401)

    def test_other_user_403(self):
        self.assertEqual(self.post('300', user='bob').status_code, 403)

    def test_non_koochainrun_template_400(self):
        self.assertEqual(self.post('302').status_code, 400)

    def test_mode_must_match_report_kind(self):
        self.assertEqual(self.post('300', {'mode': 'impact'}).status_code, 400)
        self.assertEqual(self.post('300', {'mode': 'bogus'}).status_code, 400)
        self.assertEqual(self.post('300', {'mem': '32G; rm'}).status_code, 400)

    def test_running_original_409(self):
        with open(SQUEUE_OUT, 'w') as f:
            f.write('300\n')
        self.assertEqual(self.post('300').status_code, 409)
        self.assertFalse(os.path.exists(LAST_SCRIPT))

    def test_sbatch_failure_restores_manifest(self):
        with open(SBATCH_RC, 'w') as f:
            f.write('1')
        self.assertEqual(self.post('300').status_code, 500)
        self.assertTrue(os.path.exists(self.manifest))

    def test_submit_then_job_rewrites_manifest(self):
        r = self.post('300', {'mode': 'sphere'})
        self.assertEqual(r.status_code, 201, r.get_json())
        data = r.get_json()
        self.assertEqual((data['job_id'], data['original_job_id'], data['mode']), ('5001', '300', 'sphere'))
        # 이전 매니페스트는 치워 둔다 — 매니페스트가 다시 생기면 후처리가 끝난 것
        self.assertFalse(os.path.exists(self.manifest))
        self.assertTrue(os.path.exists(self.manifest.replace('.json', '.prev.json')))
        with open(LAST_SCRIPT) as f:
            script = f.read()
        self.assertIn('#SBATCH --job-name=pp_300', script)
        self.assertIn('postprocess runner_config.json --sphere', script)
        # 후처리 잡도 원 잡 제출자 명의로 기록 — 그 잡 로그·파일에 같은 소유 검사가 통한다
        conn = sqlite3.connect(_env.DB_PATH)
        owner = conn.execute("SELECT user_id FROM job_submissions WHERE job_id='5001'").fetchone()[0]
        conn.close()
        self.assertEqual(owner, 'alice')
        self.assertEqual(self.client.get('/api/jobs/5001/files', headers=_env.bearer('alice')).status_code, 200)
        self.assertEqual(self.client.get('/api/jobs/5001/files', headers=_env.bearer('bob')).status_code, 403)

        # 만들어진 sbatch 스크립트를 그대로 돌린다(노드 대신 bash)
        env = dict(os.environ, SLURM_JOB_ID='5001', PATH=f"{SLURM_BIN}:{os.environ['PATH']}")
        run = subprocess.run(['bash', LAST_SCRIPT], capture_output=True, text=True, env=env)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        with open(self.manifest, encoding='utf-8') as f:
            m = json.load(f)
        self.assertTrue(m['ok'])
        self.assertEqual(m['job']['slurm_job_id'], '300')
        self.assertEqual(m['postprocess'], {'by': 'postprocess_job', 'rc': 0, 'report_job': None,
                                            'postprocess_job_id': '5001'})
        self.assertTrue(m['reports'][0]['present'])

    def test_admin_may_submit_for_owner(self):
        r = self.post('300', user='carol', role='admin')
        self.assertEqual(r.status_code, 201, r.get_json())


if __name__ == '__main__':
    unittest.main()
