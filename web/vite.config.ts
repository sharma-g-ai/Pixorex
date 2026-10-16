import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vitest/config'

// Mock API (npm run api:mock) listens here until the real API exists.
const MOCK_API = 'http://127.0.0.1:4010'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    proxy: {
      // The app calls /api/v1/...; Prism serves the contract paths without that prefix.
      '/api/v1': {
        target: MOCK_API,
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api\/v1/, ''),
        configure: (proxy) => {
          // The mock enforces the contract's Bearer token. Until web sign-in exists
          // (PX-01-T12), send a placeholder; a real token from the app always wins.
          proxy.on('proxyReq', (proxyReq) => {
            if (!proxyReq.getHeader('authorization')) {
              proxyReq.setHeader('Authorization', 'Bearer local-mock-token')
            }
          })
        },
      },
    },
  },
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
  },
})
