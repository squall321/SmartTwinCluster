// vite.config.ts
import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const apiUrl = env.VITE_API_URL || 'http://localhost:5000'

  return {
    base: '/cae/',
    plugins: [react()],
    server: {
      host: true,
      port: 5173,
      strictPort: true,
      proxy: {
        '/api': {
          target: apiUrl,
          changeOrigin: true,
          secure: false,
        },
      },
    },
    resolve: {
      alias: {
        '@pages': path.resolve(__dirname, './src/pages'),
        '@components': path.resolve(__dirname, './src/components'),
      },
    },
    build: {
      rollupOptions: {
        output: {
          manualChunks: {
            'vendor-react': ['react', 'react-dom', 'react-router-dom'],
            'vendor-mui': ['@mui/material', '@mui/icons-material', '@emotion/react', '@emotion/styled'],
            'vendor-3d': ['three', '@react-three/fiber', '@react-three/drei'],
            'vendor-babylon': ['@babylonjs/core', '@babylonjs/loaders', '@babylonjs/materials'],
            'vendor-plot': ['plotly.js', 'react-plotly.js'],
            'vendor-chart': ['@ant-design/charts', 'antd'],
            'vendor-flow': ['@xyflow/react', 'reactflow'],
            'vendor-utils': ['axios', 'mathjs', 'papaparse', 'zustand']
            // lodash는 직접 의존성이 아니므로 제거
          }
        }
      },
      chunkSizeWarningLimit: 2000,  // CAE는 3D 라이브러리로 인해 큼
      sourcemap: false,
      minify: 'esbuild',  // esbuild 사용 (더 빠름, Vite 내장)
      esbuild: {
        drop: mode === 'production' ? ['console', 'debugger'] : []
      }
    }
  }
});
