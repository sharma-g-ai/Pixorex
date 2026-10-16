import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { loadEnv } from 'vite'
import { defineConfig } from 'vitest/config'

// Real FastAPI (Phase E). Override with VITE_API_PROXY_TARGET=http://127.0.0.1:4010 for Prism mock.
const REAL_API = 'http://127.0.0.1:8000'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const target = (env.VITE_API_PROXY_TARGET || REAL_API).replace(/\/$/, '')
  const useMock = target.includes(':4010')

  return {
    plugins: [react(), tailwindcss()],
    server: {
      proxy: {
        // App calls /api/v1/... — FastAPI serves that prefix; Prism does not (needs rewrite).
        '/api/v1': {
          target,
          changeOrigin: true,
          rewrite: useMock ? (path) => path.replace(/^\/api\/v1/, '') : undefined,
          configure: (proxy) => {
            if (!useMock) return
            // Prism mock only: inject a placeholder when the app is in mock auth mode.
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
  }
})
