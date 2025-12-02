import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const apiUrl = env.VITE_API_URL || 'http://localhost:5010'

  return {
    plugins: [react()],
    base: '/vnc/',
    server: {
      port: 8002,
      host: '0.0.0.0',
      strictPort: true,
      proxy: {
        '/dashboardapi': {
          target: apiUrl,
          changeOrigin: true,
          rewrite: (path) => path.replace(/^\/dashboardapi/, '/api')
        }
      }
    }
  }
})
