# SH-01·02·04 회귀 테스트 — 업로드·잡 로그는 UPLOAD_BASE·JOB_LOGS_DIR(모든 노드가 보는 곳), 못 만들면 /tmp 로 물러나지 않고 기동 실패
import os
import subprocess
import sys
import tempfile
import unittest

import _env  # noqa: F401
import yaml

import job_logs_api
import job_submit_api
import shared_paths

TEMPLATE = os.path.join(_env.BACKEND_DIR, '..', 'templates', 'official', 'simulation', 'smarttwin-fullangle-drop.yaml')


class SharedPathsTest(unittest.TestCase):
    def test_job_script_logs_and_upload_copy_use_the_shared_locations(self):
        with open(TEMPLATE, encoding='utf-8') as f:
            t = yaml.safe_load(f)
        up = os.path.join(job_submit_api.UPLOAD_DIR, 'x_model.k')
        cfg = {'uploaded_files': {'model': {'path': up, 'filename': 'model.k'}}, 'slurm_overrides': {},
               'job_name': 'drop', 'web_user': 'alice'}
        script = job_submit_api.generate_slurm_script(t, cfg)
        self.assertIn(f'#SBATCH --output={shared_paths.JOB_LOGS_DIR}/%j.out', script)
        self.assertIn(f'#SBATCH --error={shared_paths.JOB_LOGS_DIR}/%j.err', script)
        self.assertIn(f'cp "{up}" "$SLURM_SUBMIT_DIR/input/model.k"', script)
        self.assertEqual(os.path.dirname(job_submit_api.UPLOAD_DIR), shared_paths.UPLOAD_BASE)

    def test_log_reader_reads_where_jobs_write(self):
        self.assertEqual(job_logs_api.LOGS_DIR, shared_paths.JOB_LOGS_DIR)

    def test_ensure_dir_refuses_instead_of_falling_back(self):
        with tempfile.NamedTemporaryFile() as f:  # 파일 자리에는 폴더를 못 만든다
            with self.assertRaises(RuntimeError) as cm:
                shared_paths.ensure_dir(os.path.join(f.name, 'slurm_uploads'))
        self.assertIn('UPLOAD_BASE', str(cm.exception))

    def test_backend_fails_to_start_when_upload_base_is_unusable(self):
        with tempfile.NamedTemporaryFile() as f:
            env = {**os.environ, 'UPLOAD_BASE': f.name}  # 파일 — slurm_uploads 를 만들 수 없다
            r = subprocess.run([sys.executable, '-c', 'import _env, job_submit_api'], cwd=os.path.dirname(__file__),
                               env=env, capture_output=True, text=True, timeout=60)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('잡 폴더를 만들 수 없다', r.stderr)
        self.assertNotIn('/tmp/slurm_uploads', r.stderr + r.stdout)


if __name__ == '__main__':
    unittest.main()
