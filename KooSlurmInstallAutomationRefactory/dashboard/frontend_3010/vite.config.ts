import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig(({ mode }) => {
  // 환경 변수 로드
  const env = loadEnv(mode, process.cwd(), '')
  const apiUrl = env.VITE_API_URL || 'http://localhost:5010'
  const wsUrl = env.VITE_WS_URL || 'http://localhost:5011'
  const authUrl = env.VITE_AUTH_URL || 'http://localhost:4430'

  return {
    plugins: [react()],
    base: '/dashboard/',
    resolve: {
      alias: {
        '@': path.resolve(__dirname, './src'),
      },
    },
    server: {
      host: '0.0.0.0',
      port: 3010,  // Frontend port
      strictPort: true,
      proxy: {
        '/dashboardapi': {
          target: apiUrl,
          changeOrigin: true,
          secure: false,
          rewrite: (path) => path.replace(/^\/dashboardapi/, '/api')
        },
        '/ws': {
          target: wsUrl,
          changeOrigin: true,
          secure: false,
          ws: true
        },
        '/auth': {
          target: authUrl,
          changeOrigin: true,
          secure: false,
        },
      },
    },
  }
})
