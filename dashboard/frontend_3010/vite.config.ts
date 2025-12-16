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
    build: {
      rollupOptions: {
        output: {
          manualChunks: {
            'vendor-react': ['react', 'react-dom', 'react-router-dom'],
            // MUI는 dashboard에 없음 - 제거
            'vendor-chart': ['recharts', 'react-hot-toast'],
            'vendor-dnd': ['react-dnd', 'react-dnd-html5-backend'],
            'vendor-3d': ['three', '@react-three/fiber', '@react-three/drei'],
            'vendor-utils': ['axios', 'zustand', 'socket.io-client'],
            'vendor-terminal': ['xterm', 'xterm-addon-fit', 'xterm-addon-web-links']
          }
        }
      },
      chunkSizeWarningLimit: 1000,
      sourcemap: false,  // 프로덕션에서 소스맵 비활성화
      minify: 'esbuild',  // esbuild 사용 (더 빠름, Vite 내장)
      esbuild: {
        drop: mode === 'production' ? ['console', 'debugger'] : []
      }
    }
  }
})
