/**
 * Axios API Client with JWT Authentication
 * Automatically adds JWT token to all API requests
 */
import axios from 'axios';
// Create Axios instance for CAE Automation API
const apiClient = axios.create({
    baseURL: '/cae/automation',
    timeout: 30000,
    headers: {
        'Content-Type': 'application/json',
    },
});
// Request interceptor: Add JWT token to all requests
apiClient.interceptors.request.use((config) => {
    const token = localStorage.getItem('jwt_token');
    if (token) {
        config.headers.Authorization = `Bearer ${token}`;
        console.log('[CAE API] Request with JWT token:', config.url);
    }
    else {
        console.warn('[CAE API] Request without JWT token:', config.url);
    }
    return config;
}, (error) => {
    console.error('[CAE API] Request error:', error);
    return Promise.reject(error);
});
// Response interceptor: Handle 401 errors
apiClient.interceptors.response.use((response) => {
    console.log('[CAE API] Response success:', response.config.url, response.status);
    return response;
}, (error) => {
    if (error.response?.status === 401) {
        console.error('[CAE API] 401 Unauthorized - Token invalid or expired');
        // Clear invalid token
        localStorage.removeItem('jwt_token');
        // Redirect to Auth Portal
        console.log('[CAE API] Redirecting to Auth Portal...');
        window.location.href = '/';
    }
    else if (error.response) {
        console.error('[CAE API] Response error:', error.response.status, error.response.data);
    }
    else if (error.request) {
        console.error('[CAE API] No response received:', error.request);
    }
    else {
        console.error('[CAE API] Error:', error.message);
    }
    return Promise.reject(error);
});
export default apiClient;
