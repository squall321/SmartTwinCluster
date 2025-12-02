import axios from 'axios';

// Use relative path for Nginx routing: /cae/automation/ -> http://localhost:5001/
const baseURL = '/cae/automation';

export const api = axios.create({
  baseURL,
});

// Request interceptor: Add JWT token to all requests
api.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem('jwt_token');

    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
      console.log('[CAE API] Request with JWT token:', config.url);
    } else {
      console.warn('[CAE API] Request without JWT token:', config.url);
    }

    return config;
  },
  (error) => {
    console.error('[CAE API] Request error:', error);
    return Promise.reject(error);
  }
);

// Response interceptor: Handle 401 errors
api.interceptors.response.use(
  (response) => {
    console.log('[CAE API] Response success:', response.config.url, response.status);
    return response;
  },
  (error) => {
    if (error.response?.status === 401) {
      console.error('[CAE API] 401 Unauthorized - Token invalid or expired');

      // Clear invalid token
      localStorage.removeItem('jwt_token');

      // Redirect to Auth Portal
      console.log('[CAE API] Redirecting to Auth Portal...');
      window.location.href = '/';
    } else if (error.response) {
      console.error('[CAE API] Response error:', error.response.status, error.response.data);
    } else if (error.request) {
      console.error('[CAE API] No response received:', error.request);
    } else {
      console.error('[CAE API] Error:', error.message);
    }

    return Promise.reject(error);
  }
);
