import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],

  // Production build에서 /app/ 경로 사용 (Nginx reverse proxy)
  base: '/app/',

  server: {
    port: 5174,
    host: true,
    proxy: {
      // kooCAEWebServer_5000 백엔드 프록시
      '/api': {
        target: 'http://localhost:5000',
        changeOrigin: true,
        secure: false,
      },
    },
  },

  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
      '@core': path.resolve(__dirname, './src/core'),
      '@apps': path.resolve(__dirname, './src/apps'),
      '@shared': path.resolve(__dirname, './src/shared'),
    },
  },

  build: {
    outDir: 'dist',
    sourcemap: true,
    target: 'esnext',  // top-level await 지원
    commonjsOptions: {
      transformMixedEsModules: true,
      ignoreTryCatch: 'remove',
    },
    rollupOptions: {
      output: {
        format: 'es',  // ES module format for top-level await
        // Embedding을 위한 chunk 분리
        manualChunks: {
          'react-vendor': ['react', 'react-dom'],
        },
      },
    },
  },

  optimizeDeps: {
    exclude: ['@novnc/novnc'],  // noVNC는 top-level await + CommonJS 혼합으로 pre-bundle 불가
    esbuildOptions: {
      target: 'esnext',
    },
  },
})
