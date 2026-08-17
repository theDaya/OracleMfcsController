import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    host: '127.0.0.1',
    port: 4173,
    proxy: {
      '/workflow-api': {
        target: 'https://localhost:8443/ords/office_mfcs_ui_app/office-workflow/v1',
        changeOrigin: true,
        secure: false,
        rewrite: (path) => path.replace(/^\/workflow-api/, ''),
      },
    },
  },
  test: {
    environment: 'jsdom',
    setupFiles: './src/test/setup.ts',
    css: true,
  },
})
