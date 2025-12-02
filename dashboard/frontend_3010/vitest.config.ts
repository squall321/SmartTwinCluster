import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import path from 'path';

export default defineConfig({
  plugins: [react()],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    
    // Optimize test execution
    pool: 'forks',
    poolOptions: {
      forks: {
        singleFork: true, // Use single process to reduce memory
      },
      threads: {
        singleThread: true,
      },
    },
    
    // Increase timeouts to prevent premature failures
    testTimeout: 20000,      // 20 seconds
    hookTimeout: 20000,      // 20 seconds
    
    // Limit concurrent tests
    maxConcurrency: 3,
    
    // Coverage configuration
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      exclude: [
        'node_modules/',
        'src/test/',
        '**/*.d.ts',
        '**/*.config.*',
        '**/mockData',
        'dist/',
      ],
    },
    
    // Isolate tests to prevent interference
    isolate: true,
    
    // Clear mocks after each test
    clearMocks: true,
    mockReset: true,
    restoreMocks: true,
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
});
