import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

// ORDS runs on the database host, over plain HTTP on 8080. Proxying through
// Vite avoids the CORS preflight.
//
// The default used to be https://localhost:8443, the adb-free container, which
// is not running and is not the deployment target - see CLAUDE.md. That default
// failed as a connection refused on every /api call, which reads like the
// console being broken rather than like it being pointed at the wrong host.
const ORDS = process.env.ORDS_URL || 'http://mdutilstst01.truworths.co.za:8080';
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
