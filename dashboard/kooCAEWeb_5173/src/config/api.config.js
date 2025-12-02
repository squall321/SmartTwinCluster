/**
 * CAE Frontend API Configuration
 */
const API_URL = import.meta.env.VITE_API_URL;
const AUTOMATION_URL = import.meta.env.VITE_AUTOMATION_URL;
const AUTH_URL = import.meta.env.VITE_AUTH_URL;
const currentHost = typeof window !== 'undefined' ? window.location.hostname : 'localhost';
export const API_CONFIG = {
    // CAE Backend
    API_BASE_URL: API_URL || `http://${currentHost}:5000`,
    // CAE Automation
    AUTOMATION_URL: AUTOMATION_URL || `http://${currentHost}:5001`,
    // Auth
    AUTH_URL: AUTH_URL || `http://${currentHost}:4430`,
    TIMEOUT: 30000,
};
export default API_CONFIG;
