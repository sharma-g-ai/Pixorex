import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vitest/config'

// Static screens only: no API yet, all data comes from src/data.
export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: { port: 5181 },
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
  },
})
