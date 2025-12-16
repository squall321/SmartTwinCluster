import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { Spin, message } from 'antd';
import BaseLayout from '../layouts/BaseLayout';
import { API_CONFIG } from '../config/api.config';
const LoginPage = ({ onLogin }) => {
    const navigate = useNavigate();
    const [searchParams] = useSearchParams();
    useEffect(() => {
        // URL에서 JWT 토큰 확인
        const token = searchParams.get('token');
        if (token) {
            // Auth Portal에서 전달받은 JWT 토큰으로 자동 로그인
            handleSSOLogin(token);
        }
        else {
            // 토큰이 없으면 Auth Portal로 리다이렉트
            redirectToAuthPortal();
        }
    }, [searchParams]);
    const handleSSOLogin = async (token) => {
        try {
            // JWT 토큰 저장
            localStorage.setItem('jwt_token', token);
            // Remove token from URL for security (prevent token exposure in browser history)
            window.history.replaceState({}, document.title, window.location.pathname);
            // JWT에서 사용자 정보 추출 (decode)
            const payload = parseJWT(token);
            if (payload) {
                localStorage.setItem('isLoggedIn', 'true');
                localStorage.setItem('username', payload.sub || payload.username || 'user');
                localStorage.setItem('user_info', JSON.stringify({
                    username: payload.sub || payload.username,
                    email: payload.email,
                    groups: payload.groups || [],
                }));
                message.success('로그인 성공!');
                onLogin();
                navigate('/');
            }
            else {
                throw new Error('Invalid token');
            }
        }
        catch (err) {
            console.error('SSO login failed:', err);
            message.error('로그인 실패: ' + (err.message || '알 수 없는 오류'));
            redirectToAuthPortal();
        }
    };
    const redirectToAuthPortal = () => {
        // Auth Portal로 리다이렉트 (현재 URL을 리턴 URL로 전달)
        const currentUrl = window.location.href.split('?')[0]; // 쿼리 파라미터 제거
        const authUrl = API_CONFIG.AUTH_URL || 'http://localhost:4431';
        // Auth Portal에 돌아올 URL 전달
        window.location.href = `${authUrl}?redirect=${encodeURIComponent(currentUrl)}`;
    };
    const parseJWT = (token) => {
        try {
            const base64Url = token.split('.')[1];
            const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
            const jsonPayload = decodeURIComponent(atob(base64)
                .split('')
                .map(c => '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2))
                .join(''));
            return JSON.parse(jsonPayload);
        }
        catch (error) {
            console.error('Failed to parse JWT:', error);
            return null;
        }
    };
    return (_jsx(BaseLayout, { isLoggedIn: false, children: _jsx("div", { style: {
                display: 'flex',
                justifyContent: 'center',
                alignItems: 'center',
                width: '100%',
                height: '100%',
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: _jsxs("div", { style: { textAlign: 'center' }, children: [_jsx(Spin, { size: "large" }), _jsx("p", { style: { marginTop: '1rem', color: '#666' }, children: "Auth Portal\uB85C \uB9AC\uB2E4\uC774\uB809\uD2B8 \uC911..." })] }) }) }));
};
export default LoginPage;
