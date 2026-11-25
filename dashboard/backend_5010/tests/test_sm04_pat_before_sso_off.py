# SM-04 회귀 테스트 — SSO 꺼짐이어도 PAT(kst_)는 그 사람으로 풀리고, 틀린 PAT 는 admin 이 아니라 401
import unittest
from unittest import mock

import _env  # noqa: F401
from flask import Flask, g, jsonify

import mcp_token
import mcp_token_api
from middleware import jwt_middleware
from middleware.jwt_middleware import optional_jwt


class PatBeforeSsoOffTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        mcp_token.ensure_token_table()
        app = Flask(__name__)
        app.register_blueprint(mcp_token_api.mcp_token_bp)

        @app.route('/optional')
        @optional_jwt
        def _optional():
            return jsonify({'user': g.user})

        cls.client = app.test_client()
        _, cls.pat = mcp_token.create_token({'username': 'hong', 'role': 'user'}, 'sm04')

    def _me(self, token=None):
        headers = {'Authorization': f'Bearer {token}'} if token else {}
        return self.client.get('/api/me', headers=headers)

    def test_sso_off_pat_resolves_to_its_owner(self):
        with mock.patch.object(jwt_middleware, 'SSO_ENABLED', False):
            r = self._me(self.pat)
        self.assertEqual(r.status_code, 200)
        self.assertEqual((r.json['username'], r.json['auth']), ('hong', 'pat'))

    def test_sso_off_without_header_stays_admin_for_the_web(self):
        with mock.patch.object(jwt_middleware, 'SSO_ENABLED', False):
            r = self._me()
        self.assertEqual(r.status_code, 200)
        self.assertEqual((r.json['username'], r.json['auth']), ('admin', 'sso_off'))

    def test_sso_off_wrong_pat_is_401_not_admin(self):
        with mock.patch.object(jwt_middleware, 'SSO_ENABLED', False):
            r = self._me('kst_wrong')
        self.assertEqual(r.status_code, 401)

    def test_sso_on_pat_still_resolves(self):
        r = self._me(self.pat)
        self.assertEqual((r.status_code, r.json['username'], r.json['auth']), (200, 'hong', 'pat'))

    def test_optional_jwt_sso_off_wrong_pat_is_anonymous_not_admin(self):
        with mock.patch.object(jwt_middleware, 'SSO_ENABLED', False):
            bad = self.client.get('/optional', headers={'Authorization': 'Bearer kst_wrong'})
            good = self.client.get('/optional', headers={'Authorization': f'Bearer {self.pat}'})
        self.assertIsNone(bad.json['user'])
        self.assertEqual((good.json['user']['username'], good.json['user']['auth']), ('hong', 'pat'))


if __name__ == '__main__':
    unittest.main()
