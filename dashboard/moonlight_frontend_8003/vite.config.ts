import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig(({ mode }) => ({
  plugins: [react()],
  server: {
    port: 8003,
    host: '0.0.0.0',
    proxy: {
      '/api/moonlight': {
        target: 'http://localhost:8004',
        changeOrigin: true,
      }
    }
  },
  base: '/moonlight/',
  build: {
    outDir: 'dist',
    sourcemap: false,  // 프로덕션 소스맵 비활성화
    rollupOptions: {
      output: {
        manualChunks: {
          'vendor-react': ['react', 'react-dom'],
          'vendor-mui': ['@mui/material', '@mui/icons-material', '@emotion/react', '@emotion/styled'],
          'vendor-utils': ['axios']
        }
      }
    },
    minify: 'esbuild',  // esbuild 사용 (더 빠름)
    esbuild: {
      drop: mode === 'production' ? ['console', 'debugger'] : []
    }
  }
}))
