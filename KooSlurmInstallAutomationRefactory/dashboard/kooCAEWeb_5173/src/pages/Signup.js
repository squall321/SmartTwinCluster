import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
// src/pages/Signup.tsx
import { api } from '../api/axiosClient';
import { useNavigate } from 'react-router-dom';
import { Form, Input, Button, message } from 'antd';
import BaseLayout from '../layouts/BaseLayout';
const SignupPage = () => {
    const navigate = useNavigate();
    const handleSignup = async (values) => {
        try {
            const res = await api.post('/api/signup', values);
            if (res.data.success) {
                message.success('회원가입 성공! 로그인해주세요');
                navigate('/login');
            }
            else {
                message.error(res.data.message);
            }
        }
        catch (err) {
            message.error(err.response?.data?.message || '회원가입 실패');
        }
    };
    return (_jsx(BaseLayout, { isLoggedIn: false, children: _jsx("div", { style: {
                display: 'flex',
                justifyContent: 'center',
                alignItems: 'center',
                width: '100%',
                minHeight: '100vh',
                background: '#f0f2f5',
                borderRadius: '24px',
            }, children: _jsxs(Form, { onFinish: handleSignup, layout: "vertical", style: {
                    width: '100%',
                    maxWidth: 400,
                    background: '#fff',
                    padding: '2rem',
                    borderRadius: '8px',
                    boxShadow: '0 0 10px rgba(0,0,0,0.1)',
                }, children: [_jsx("h2", { style: { textAlign: 'center' }, children: "\uD68C\uC6D0\uAC00\uC785" }), _jsx(Form.Item, { name: "username", label: "\uC544\uC774\uB514", rules: [{ required: true, message: '아이디를 입력해주세요' }], children: _jsx(Input, { placeholder: "\uC544\uC774\uB514\uB97C \uC785\uB825\uD558\uC138\uC694" }) }), _jsx(Form.Item, { name: "email", label: "\uC774\uBA54\uC77C", rules: [{ required: true, type: 'email', message: '유효한 이메일을 입력해주세요' }], children: _jsx(Input, { placeholder: "example@email.com" }) }), _jsx(Form.Item, { name: "password", label: "\uBE44\uBC00\uBC88\uD638", rules: [{ required: true, message: '비밀번호를 입력해주세요' }], children: _jsx(Input.Password, { placeholder: "\uBE44\uBC00\uBC88\uD638 \uC785\uB825" }) }), _jsx(Form.Item, { name: "confirm", label: "\uBE44\uBC00\uBC88\uD638 \uD655\uC778", dependencies: ['password'], hasFeedback: true, rules: [
                            { required: true, message: '비밀번호 확인을 입력해주세요' },
                            ({ getFieldValue }) => ({
                                validator(_, value) {
                                    if (!value || getFieldValue('password') === value) {
                                        return Promise.resolve();
                                    }
                                    return Promise.reject(new Error('비밀번호가 일치하지 않습니다.'));
                                }
                            })
                        ], children: _jsx(Input.Password, { placeholder: "\uBE44\uBC00\uBC88\uD638 \uC7AC\uC785\uB825" }) }), _jsx(Form.Item, { name: "name", label: "\uC774\uB984", rules: [{ required: true, message: '이름을 입력해주세요' }], children: _jsx(Input, { placeholder: "\uC774\uB984\uC744 \uC785\uB825\uD558\uC138\uC694" }) }), _jsx(Form.Item, { name: "department", label: "\uC18C\uC18D", children: _jsx(Input, { placeholder: "\uC18C\uC18D \uBD80\uC11C\uB97C \uC785\uB825\uD558\uC138\uC694" }) }), _jsx(Form.Item, { children: _jsx(Button, { htmlType: "submit", type: "primary", block: true, children: "\uAC00\uC785\uD558\uAE30" }) })] }) }) }));
};
export default SignupPage;
