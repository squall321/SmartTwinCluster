# 잡 파일 REST(job_logs_api) 인증·소유 검사·경로 검사·다운로드 티켓 회귀 테스트
import os
import unittest

import _env  # noqa: F401  (env 고정이 블루프린트 import 보다 먼저)
from flask import Flask

import job_logs_api


def _make_result(name, files):
    d = os.path.join(_env.ROOT, 'single', 'alice', name)
    for rel, body in files.items():
        p = os.path.join(d, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'w') as f:
            f.write(body)
    return d


class JobFilesAuthTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        _env.init_db()
        cls.dir_12 = _make_result('A_12', {'output/sphere_report.html': '<html>12</html>'})
        cls.dir_123 = _make_result('A_123', {'output/sphere_report.html': '<html>123</html>'})
        _env.add_submission('12', 'alice', cls.dir_12)
        _env.add_submission('123', 'bob', cls.dir_123)
        _env.add_submission('77', 'anonymous', cls.dir_123)
        with open(os.path.join(os.environ['JOB_LOGS_DIR'], '12.out'), 'w') as f:
            f.write('driver log 12\n')
        with open(os.path.join(os.environ['JOB_LOGS_DIR'], '123.out'), 'w') as f:
            f.write('driver log 123\n')
        app = Flask(__name__)
        app.register_blueprint(job_logs_api.job_logs_bp)
        cls.client = app.test_client()

    def get(self, url, headers=None):
        return self.client.get(url, headers=headers or {})

    def test_no_token_401(self):
        for url in ('/api/jobs/12/files', '/api/jobs/12/files/view?path=output/sphere_report.html',
                    '/api/jobs/12/files/download?path=output/sphere_report.html', '/api/jobs/12/logs',
                    '/api/jobs/12/logs/tail', '/api/jobs/12/info', '/api/jobs/12/files/download-all',
                    '/api/jobs/12/logs/stream'):
            self.assertEqual(self.get(url).status_code, 401, url)

    def test_garbage_token_401(self):
        r = self.get('/api/jobs/12/files', {'Authorization': 'Bearer not-a-jwt'})
        self.assertEqual(r.status_code, 401)

    def test_owner_200_other_403(self):
        url = '/api/jobs/12/files/download?path=output/sphere_report.html'
        r = self.get(url, _env.bearer('alice'))
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data, b'<html>12</html>')
        self.assertEqual(self.get(url, _env.bearer('bob')).status_code, 403)

    def test_admin_reads_any(self):
        r = self.get('/api/jobs/123/files/download?path=output/sphere_report.html', _env.bearer('carol', role='admin'))
        self.assertEqual(r.status_code, 200)

    def test_anonymous_owner_admin_only(self):
        self.assertEqual(self.get('/api/jobs/77/files', _env.bearer('anonymous')).status_code, 403)

    def test_unrecorded_job_admin_only(self):
        self.assertEqual(self.get('/api/jobs/999/files', _env.bearer('alice')).status_code, 403)

    def test_sibling_prefix_traversal_403(self):
        for route in ('download', 'view'):
            r = self.get(f'/api/jobs/12/files/{route}?path=../A_123/output/sphere_report.html', _env.bearer('alice'))
            self.assertEqual(r.status_code, 403, route)

    def test_logs_dir_traversal_403(self):
        r = self.get('/api/jobs/12/files/download?path=' + os.path.join(os.environ['JOB_LOGS_DIR'], '123.out'),
                     _env.bearer('alice'))
        self.assertEqual(r.status_code, 403)

    def test_download_stdout_200(self):
        r = self.get('/api/jobs/12/files/download?path=stdout', _env.bearer('alice'))
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data, b'driver log 12\n')

    def test_missing_file_404(self):
        r = self.get('/api/jobs/12/files/download?path=output/return_manifest.json', _env.bearer('alice'))
        self.assertEqual(r.status_code, 404)

    def test_download_ticket(self):
        r = self.client.post('/api/jobs/12/files/download-ticket', headers=_env.bearer('alice'))
        self.assertEqual(r.status_code, 200)
        ticket = r.get_json()['ticket']
        ok = self.get(f'/api/jobs/12/files/download?path=output/sphere_report.html&ticket={ticket}')
        self.assertEqual(ok.status_code, 200)
        # 다른 잡에는 안 통한다
        self.assertEqual(self.get(f'/api/jobs/123/files/download?path=x&ticket={ticket}').status_code, 401)
        # 다른 API 의 Bearer 로도 안 통한다(서명 키가 다르다)
        self.assertEqual(self.get('/api/jobs/12/files', {'Authorization': f'Bearer {ticket}'}).status_code, 401)
        # 남의 잡 티켓은 발급되지 않는다
        r = self.client.post('/api/jobs/12/files/download-ticket', headers=_env.bearer('bob'))
        self.assertEqual(r.status_code, 403)

    def test_expired_ticket_401(self):
        import jwt
        from datetime import datetime, timedelta
        past = datetime.utcnow() - timedelta(minutes=5)
        t = jwt.encode({'sub': 'alice', 'role': 'user', 'job_id': '12', 'scope': 'job-download',
                        'iat': past, 'exp': past + timedelta(seconds=1)},
                       job_logs_api._DOWNLOAD_TICKET_KEY, algorithm='HS256')
        self.assertEqual(self.get(f'/api/jobs/12/files/download?path=stdout&ticket={t}').status_code, 401)


if __name__ == '__main__':
    unittest.main()
