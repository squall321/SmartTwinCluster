import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const apiUrl = env.VITE_API_URL || 'http://localhost:4430'
  const vncApiUrl = env.VITE_VNC_API_URL || 'http://localhost:5010'

  return {
    plugins: [react()],
    server: {
      port: 4431,
      host: '0.0.0.0',
      proxy: {
        '/auth': {
          target: apiUrl,
          changeOrigin: true
        },
        '/dashboardapi': {
          target: vncApiUrl,
          changeOrigin: true,
          rewrite: (path) => path.replace(/^\/dashboardapi/, '/api')
        },
        '/api': {
          target: vncApiUrl,
          changeOrigin: true
        }
      }
    }
  }
})
