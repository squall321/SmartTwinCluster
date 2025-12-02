// src/pages/Signup.tsx
import { api } from '../api/axiosClient';
import { useNavigate } from 'react-router-dom';
import { Form, Input, Button, message } from 'antd';
import BaseLayout from '../layouts/BaseLayout';

const SignupPage = () => {
  const navigate = useNavigate();

  const handleSignup = async (values: any) => {
    try {
      const res = await api.post('/api/signup', values);
      if (res.data.success) {
        message.success('회원가입 성공! 로그인해주세요');
        navigate('/login');
      } else {
        message.error(res.data.message);
      }
    } catch (err: any) {
      message.error(err.response?.data?.message || '회원가입 실패');
    }
  };

  return (
    <BaseLayout isLoggedIn={false}>
      <div style={{
        display: 'flex',
        justifyContent: 'center',
        alignItems: 'center',
        width: '100%',
        minHeight: '100vh',
        background: '#f0f2f5',
        borderRadius: '24px',
      }}>
        <Form
          onFinish={handleSignup}
          layout="vertical"
          style={{
            width: '100%',
            maxWidth: 400,
            background: '#fff',
            padding: '2rem',
            borderRadius: '8px',
            boxShadow: '0 0 10px rgba(0,0,0,0.1)',
          }}
        >
          <h2 style={{ textAlign: 'center' }}>회원가입</h2>

            <Form.Item
            name="username"
            label="아이디"
            rules={[{ required: true, message: '아이디를 입력해주세요' }]}
            >
            <Input placeholder="아이디를 입력하세요" />
            </Form.Item>

            <Form.Item
            name="email"
            label="이메일"
            rules={[{ required: true, type: 'email', message: '유효한 이메일을 입력해주세요' }]}
            >
            <Input placeholder="example@email.com" />
            </Form.Item>

            <Form.Item
            name="password"
            label="비밀번호"
            rules={[{ required: true, message: '비밀번호를 입력해주세요' }]}
            >
            <Input.Password placeholder="비밀번호 입력" />
            </Form.Item>

            <Form.Item
            name="confirm"
            label="비밀번호 확인"
            dependencies={['password']}
            hasFeedback
            rules={[
                { required: true, message: '비밀번호 확인을 입력해주세요' },
                ({ getFieldValue }) => ({
                validator(_, value) {
                    if (!value || getFieldValue('password') === value) {
                    return Promise.resolve();
                    }
                    return Promise.reject(new Error('비밀번호가 일치하지 않습니다.'));
                }
                })
            ]}
            >
            <Input.Password placeholder="비밀번호 재입력" />
            </Form.Item>

            <Form.Item
            name="name"
            label="이름"
            rules={[{ required: true, message: '이름을 입력해주세요' }]}
            >
            <Input placeholder="이름을 입력하세요" />
            </Form.Item>

          <Form.Item name="department" label="소속">
            <Input placeholder="소속 부서를 입력하세요" />
          </Form.Item>

          <Form.Item>
            <Button htmlType="submit" type="primary" block>
              가입하기
            </Button>
          </Form.Item>
        </Form>
      </div>
    </BaseLayout>
  );
};

export default SignupPage;
