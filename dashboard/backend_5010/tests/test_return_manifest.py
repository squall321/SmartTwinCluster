# 귀환 매니페스트 작성기와 두 드라이버 템플릿 post_exec(리포트 잡 대기·매니페스트·exit 3) 회귀 테스트
import json
import os
import shutil
import subprocess
import tempfile
import unittest

import _env  # noqa: F401
import yaml

import return_manifest

TEMPLATES = os.path.join(_env.BACKEND_DIR, '..', 'templates', 'official', 'simulation')
REAL_KCR = '/data/SmartTwinPreprocessor/bin/KooChainRun'


def _read_manifest(result_dir):
    with open(os.path.join(result_dir, 'output', 'return_manifest.json'), encoding='utf-8') as f:
        return json.load(f)


class WriterTest(unittest.TestCase):
    def setUp(self):
        self.rd = tempfile.mkdtemp(prefix='rm_')
        os.makedirs(os.path.join(self.rd, 'output'))

    def tearDown(self):
        shutil.rmtree(self.rd, ignore_errors=True)

    def run_main(self, *extra):
        return return_manifest.main(['--result-dir', self.rd, '--job-id', '42', '--job-name', 'drop',
                                     '--web-user', 'alice', '--sim-type', 'fullangle_drop', *extra])

    def test_present(self):
        html = os.path.join(self.rd, 'output', 'sphere_report.html')
        with open(html, 'w') as f:
            f.write('<html/>')
        self.assertEqual(self.run_main('--expect', 'sphere', '--postprocess', 'driver', '--pp-rc', '0'), 0)
        m = _read_manifest(self.rd)
        self.assertEqual((m['schema'], m['version'], m['ok']), ('smarttwin.return_manifest', 1, True))
        r = m['reports'][0]
        self.assertEqual((r['path'], r['present'], r['size']), ('output/sphere_report.html', True, 7))
        self.assertEqual(len(r['sha256']), 64)
        self.assertEqual(m['job']['slurm_job_id'], '42')
        self.assertEqual(m['postprocess']['rc'], 0)

    def test_missing_with_err_tail(self):
        with open(os.path.join(self.rd, 'output', 'sphere_report.slurm.err'), 'w') as f:
            f.write(''.join(f'line {i}\n' for i in range(30)) + '[sphere_report] ERROR: SIF not found\n')
        self.assertEqual(self.run_main('--expect', 'sphere', '--postprocess', 'driver', '--pp-rc', '0'),
                         return_manifest.EXIT_REPORT_MISSING)
        m = _read_manifest(self.rd)
        r = m['reports'][0]
        self.assertFalse(m['ok'])
        self.assertFalse(r['present'])
        self.assertIn('HTML 없음', r['reason'])
        tail = r['log_tail']['output/sphere_report.slurm.err']
        self.assertEqual(len(tail), return_manifest.LOG_TAIL_LINES)
        self.assertEqual(tail[-1], '[sphere_report] ERROR: SIF not found')

    def test_disabled_is_ok(self):
        self.assertEqual(self.run_main('--expect', 'impact', '--postprocess', 'disabled'), 0)
        m = _read_manifest(self.rd)
        self.assertTrue(m['ok'])
        self.assertIn('후처리 꺼짐', m['reports'][0]['reason'])

    def test_early_exit_reason(self):
        self.run_main('--expect', 'sphere', '--stage', 'early_exit', '--driver-rc', '1')
        m = _read_manifest(self.rd)
        self.assertEqual((m['stage'], m['driver_rc']), ('early_exit', 1))
        self.assertIn('리포트 단계 전에 끝남', m['reports'][0]['reason'])

    def test_no_tmp_left_behind(self):
        self.run_main('--expect', 'sphere', '--postprocess', 'disabled')
        self.assertEqual(sorted(os.listdir(os.path.join(self.rd, 'output'))), ['return_manifest.json'])

    def test_shell_function_runs_from_stdin(self):
        """잡 스크립트에 심기는 함수 그대로(bash → python3 -) 돌려 본다."""
        script = return_manifest.shell_function() + \
            f'write_return_manifest --result-dir "{self.rd}" --sim-type partial_impact --expect impact ' \
            '--postprocess disabled; echo "rc=$?"\n'
        r = subprocess.run(['bash', '-c', script], capture_output=True, text=True)
        self.assertIn('rc=0', r.stdout, r.stderr)
        self.assertEqual(_read_manifest(self.rd)['job']['sim_type'], 'partial_impact')


class DriverPostExecTest(unittest.TestCase):
    """템플릿의 pre_exec trap·post_exec 를 bash 로 돌린다 — KooChainRun·squeue·sacct 는 대역."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix='drv_')
        self.rd = os.path.join(self.tmp, 'result')
        self.bin = os.path.join(self.tmp, 'bin')
        os.makedirs(os.path.join(self.rd, 'output'))
        os.makedirs(self.bin)
        self.kcr_log = os.path.join(self.tmp, 'kcr.log')
        self._stub('KooChainRun', f'echo "$@" >> {self.kcr_log}; exit 0')
        self._stub('squeue', 'exit 0')                       # 큐에 남은 잡 없음
        self._stub('sacct', 'echo "COMPLETED|0:0"')
        with open(os.path.join(self.rd, 'runner_config.json'), 'w') as f:
            json.dump({'postprocess': {'enabled': True}}, f)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _stub(self, name, body):
        p = os.path.join(self.bin, name)
        with open(p, 'w') as f:
            f.write(f'#!/bin/bash\n{body}\n')
        os.chmod(p, 0o755)

    def _script(self, template_file):
        with open(os.path.join(TEMPLATES, template_file), encoding='utf-8') as f:
            t = yaml.safe_load(f)
        return {k: t['script'][k].replace(REAL_KCR, os.path.join(self.bin, 'KooChainRun'))
                for k in ('pre_exec', 'post_exec')}

    def _run(self, body, env_extra=None):
        script = return_manifest.shell_function() + body
        env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}", RESULT_DIR=self.rd,
                   SLURM_JOB_ID='900', SLURM_JOB_NAME='drop', WEB_USER='alice', **(env_extra or {}))
        return subprocess.run(['bash', '-c', script], capture_output=True, text=True, env=env, cwd=self.rd)

    def _submit_log(self, text):
        with open(os.path.join(self.rd, 'submit.log'), 'w') as f:
            f.write(text)

    def test_fullangle_report_job_present_exit0(self):
        self._submit_log('Submitted batch job 901\n  → Sphere Job ID: 902\n')
        with open(os.path.join(self.rd, 'output', 'sphere_report.html'), 'w') as f:
            f.write('<html/>')
        r = self._run(self._script('smarttwin-fullangle-drop.yaml')['post_exec'])
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        m = _read_manifest(self.rd)
        self.assertTrue(m['ok'])
        self.assertEqual(m['postprocess']['by'], 'report_job')
        self.assertEqual(m['postprocess']['report_job'], {'id': '902', 'state': 'COMPLETED', 'exit_code': '0:0'})
        with open(self.kcr_log) as f:
            self.assertNotIn('postprocess', f.read())   # 리포트 잡이 정본 — 드라이버는 다시 돌리지 않는다

    def test_fullangle_report_missing_exit3(self):
        self._submit_log('  → Sphere Job ID: 902\n')
        self._stub('sacct', 'echo "FAILED|1:0"')
        r = self._run(self._script('smarttwin-fullangle-drop.yaml')['post_exec'])
        self.assertEqual(r.returncode, 3, r.stdout + r.stderr)
        m = _read_manifest(self.rd)
        self.assertFalse(m['ok'])
        self.assertIn('FAILED', m['reports'][0]['reason'])

    def test_no_report_job_driver_postprocess(self):
        self._submit_log('Submitted batch job 901\n')
        r = self._run(self._script('smarttwin-fullangle-drop.yaml')['post_exec'])
        self.assertEqual(r.returncode, 3)
        with open(self.kcr_log) as f:
            self.assertIn('postprocess runner_config.json --all', f.read())
        self.assertEqual(_read_manifest(self.rd)['postprocess'], {
            'by': 'driver', 'rc': 0, 'report_job': None, 'postprocess_job_id': None})

    def test_scenario_postprocess_disabled_exit0(self):
        with open(os.path.join(self.rd, 'runner_config.json'), 'w') as f:
            json.dump({'postprocess': {'enabled': False}}, f)
        self._submit_log('')
        r = self._run(self._script('smarttwin-partial-impact.yaml')['post_exec'])
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        m = _read_manifest(self.rd)
        self.assertEqual((m['postprocess']['by'], m['reports'][0]['kind']), ('disabled', 'impact'))

    def test_partial_impact_label(self):
        self._submit_log('  → Impact Job ID: 903\n')
        with open(os.path.join(self.rd, 'output', 'impact_report.html'), 'w') as f:
            f.write('<html/>')
        r = self._run(self._script('smarttwin-partial-impact.yaml')['post_exec'])
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(_read_manifest(self.rd)['postprocess']['report_job']['id'], '903')

    def test_early_exit_trap(self):
        pre = self._script('smarttwin-fullangle-drop.yaml')['pre_exec']
        trap_line = next(line for line in pre.splitlines() if line.startswith('trap '))
        r = self._run(trap_line + '\nexit 1\n')
        self.assertEqual(r.returncode, 1)
        m = _read_manifest(self.rd)
        self.assertEqual((m['stage'], m['driver_rc'], m['ok']), ('early_exit', 1, False))

    def test_trap_keeps_post_exec_manifest(self):
        self._submit_log('  → Sphere Job ID: 902\n')
        s = self._script('smarttwin-fullangle-drop.yaml')
        trap_line = next(line for line in s['pre_exec'].splitlines() if line.startswith('trap '))
        r = self._run(trap_line + '\n' + s['post_exec'])
        self.assertEqual(r.returncode, 3)
        self.assertEqual(_read_manifest(self.rd)['stage'], 'complete')


class ScriptEmbedTest(unittest.TestCase):
    def test_generate_slurm_script_embeds_writer_only_when_used(self):
        import job_submit_api
        with open(os.path.join(TEMPLATES, 'smarttwin-fullangle-drop.yaml'), encoding='utf-8') as f:
            t = yaml.safe_load(f)
        cfg = {'uploaded_files': {}, 'slurm_overrides': {}, 'job_name': 'drop', 'web_user': 'alice'}
        script = job_submit_api.generate_slurm_script(t, cfg)
        self.assertIn('write_return_manifest() {', script)
        self.assertLess(script.index('write_return_manifest() {'), script.index('# Pre-execution'))
        r = subprocess.run(['bash', '-n'], input=script, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        t['script'] = {'pre_exec': 'true', 'main_exec': 'true', 'post_exec': 'true'}
        self.assertNotIn('write_return_manifest', job_submit_api.generate_slurm_script(t, cfg))


if __name__ == '__main__':
    unittest.main()
