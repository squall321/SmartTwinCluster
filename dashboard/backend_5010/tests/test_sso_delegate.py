# 표준 위임 창구(/api/auth/sso·/verify) 회귀 테스트 — 비밀·이메일 규칙·클라이언트·회수·발급 토큰의 실제 통과
import os
import sqlite3
import unittest

import _env  # noqa: F401
from flask import Flask

import audit_log
import job_logs_api
import mcp_token
import sso_delegate_api

SECRET = 'gw-secret'


def _hdr(email='koo.park@ax.samsung.com', client='dynaforge', secret=SECRET, delegate=None):
    h = {'X-Heax-Gateway-Secret': secret, 'X-Heax-User-Email': email, 'X-Heax-Client': client}
    if delegate is not None:
        h['X-Hwax-Delegate-Email'] = delegate
    return h


class SsoDelegateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        mcp_token.ensure_token_table()
        audit_log.ensure_audit_table()
        app = Flask(__name__)
        app.register_blueprint(sso_delegate_api.sso_delegate_bp)
        app.register_blueprint(job_logs_api.job_logs_bp)
        cls.client = app.test_client()

    def setUp(self):
        os.environ['HEAX_GATEWAY_SECRET'] = SECRET
        os.environ.pop('SSO_DELEGATE_CLIENTS', None)
        conn = sqlite3.connect(_env.DB_PATH)
        conn.execute('DELETE FROM personal_access_tokens')
        conn.commit()
        conn.close()

    def mint(self, **kw):
        return self.client.post('/api/auth/sso', headers=_hdr(**kw))

    def test_verify(self):
        self.assertEqual(self.client.post('/api/auth/sso/verify', headers=_hdr()).status_code, 204)
        self.assertEqual(self.client.post('/api/auth/sso/verify', headers=_hdr(secret='nope')).status_code, 401)
        self.assertEqual(self.client.post('/api/auth/sso/verify').status_code, 401)
        os.environ['HEAX_GATEWAY_SECRET'] = ''
        self.assertEqual(self.client.post('/api/auth/sso/verify', headers=_hdr()).status_code, 404)
        self.assertEqual(self.mint().status_code, 404)

    def test_mint_wrong_secret_401(self):
        self.assertEqual(self.mint(secret='nope').status_code, 401)

    def test_mint_identity(self):
        r = self.mint(email='Koo.Park@AX.samsung.com')
        self.assertEqual(r.status_code, 200, r.get_json())
        data = r.get_json()
        self.assertTrue(data['access_token'].startswith('kst_'))
        self.assertEqual((data['expires_in'], data['username'], data['client']), (3600, 'koo.park', 'dynaforge'))
        ident = mcp_token.resolve_token(data['access_token'])
        self.assertEqual((ident['username'], ident['role'], ident['permissions'], ident['email']),
                         ('koo.park', 'user', ['dashboard'], 'koo.park@ax.samsung.com'))
        # 사용자의 'MCP 토큰' 목록에 보인다(지울 수 있다)
        self.assertEqual([t['name'] for t in mcp_token.list_tokens('koo.park')], ['위임: dynaforge'])
        # 감사 기록
        conn = sqlite3.connect(_env.DB_PATH)
        row = conn.execute("SELECT username, target FROM audit_log WHERE action='token.delegate' "
                           "ORDER BY id DESC LIMIT 1").fetchone()
        conn.close()
        self.assertEqual(row, ('delegate:dynaforge', 'koo.park'))

    def test_delegate_header_wins(self):
        r = self.mint(email='svc@portal.local', delegate='alice@corp.com')
        self.assertEqual(r.get_json()['username'], 'alice')

    def test_rejected_emails(self):
        for email in ('', 'no-at-sign', 'a@b@c', '@corp.com', 'x@', '.hidden@corp.com', 'admin@corp.com',
                      'anonymous@corp.com', 'root@corp.com', 'a/b@corp.com', ('x' * 33) + '@corp.com'):
            self.assertEqual(self.mint(email=email).status_code, 400, email)
        self.assertEqual(mcp_token.list_tokens('admin'), [])

    def test_client_allowlist(self):
        self.assertEqual(self.mint(client='').status_code, 400)
        self.assertEqual(self.mint(client='random').status_code, 400)
        self.assertEqual(self.mint(client='gateway').status_code, 400)   # 이름을 백엔드별로 가른 뒤 아무도 안 보낸다
        self.assertEqual(self.mint(client='GATEWAY-SMART-TWIN-MCP').status_code, 200)
        self.assertEqual(self.mint(client='gateway-smart-twin-cluster').status_code, 200)
        os.environ['SSO_DELEGATE_CLIENTS'] = 'dynaforge,deliberation'
        self.assertEqual(self.mint(client='deliberation').status_code, 200)
        self.assertEqual(self.mint(client='gateway-smart-twin-mcp').status_code, 400)

    def test_rotation_per_client(self):
        first = self.mint().get_json()['access_token']
        other = self.mint(client='gateway-smart-twin-mcp').get_json()['access_token']
        cluster = self.mint(client='gateway-smart-twin-cluster').get_json()['access_token']
        second = self.mint().get_json()['access_token']
        self.assertIsNone(mcp_token.resolve_token(first))          # 같은 클라이언트 직전 것은 회수
        self.assertIsNotNone(mcp_token.resolve_token(second))
        self.assertIsNotNone(mcp_token.resolve_token(other))        # 다른 클라이언트는 그대로
        self.assertIsNotNone(mcp_token.resolve_token(cluster))      # 게이트웨이 두 위임도 서로 안 죽인다
        self.assertEqual(len(mcp_token.list_tokens('koo.park')), 3)

    def test_expired_token_rejected(self):
        tok = self.mint().get_json()['access_token']
        conn = sqlite3.connect(_env.DB_PATH)
        conn.execute("UPDATE personal_access_tokens SET expires_at='2000-01-01 00:00:00'")
        conn.commit()
        conn.close()
        self.assertIsNone(mcp_token.resolve_token(tok))

    def test_minted_token_opens_own_job_only(self):
        """SSO 켜짐에서 발급 토큰이 보호 라우트를 실제로 통과하고, 소유 검사를 그대로 받는다."""
        _env.init_db()
        rd = os.path.join(_env.ROOT, 'single', 'koo.park', 'drop_700')
        os.makedirs(os.path.join(rd, 'output'), exist_ok=True)
        _env.add_submission('700', 'koo.park', rd)
        _env.add_submission('701', 'someone', rd)
        tok = self.mint().get_json()['access_token']
        h = {'Authorization': f'Bearer {tok}'}
        self.assertEqual(self.client.get('/api/jobs/700/files', headers=h).status_code, 200)
        self.assertEqual(self.client.get('/api/jobs/701/files', headers=h).status_code, 403)


if __name__ == '__main__':
    unittest.main()
