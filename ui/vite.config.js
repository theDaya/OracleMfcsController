import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

// ORDS runs on the adb-free container with a self-signed certificate.
// Proxying through Vite avoids both the CORS preflight and the cert warning.
const ORDS = process.env.ORDS_URL || 'https://localhost:8443';
const SCHEMA = process.env.ORDS_SCHEMA || 'mfcs_integration';

export default defineConfig({
  plugins: [react()],
  // Serves docs/mfcs-openapi/openapi.json at /openapi.json in dev and copies it on build,
  // so the spec lives in exactly one place in the repo.
  publicDir: path.resolve(here, '../docs/mfcs-openapi'),
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: ORDS,
        changeOrigin: true,
        secure: false,
        rewrite: (p) => p.replace(/^\/api/, `/ords/${SCHEMA}/mfcs/v1`),
      },
    },
  },
});
