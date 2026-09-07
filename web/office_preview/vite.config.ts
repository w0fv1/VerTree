import { createServer } from 'vite'
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import { previewCapabilitiesPlugin } from '../../vendor/office-viewer/office-viewer-app/scripts/previewCapabilitiesPlugin'
import { readFileSync } from 'node:fs'

const dependencies = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf8')).dependencies

export default defineConfig({
  base: './',
  publicDir: '../../vendor/office-viewer/office-viewer-app/public',
  plugins: [react(), previewCapabilitiesPlugin(createServer)],
  resolve: { dedupe: Object.keys(dependencies) },
  test: { environment: 'jsdom', include: ['src/**/*.test.ts'] },
  build: {
    outDir: '../../assets/office_viewer',
    emptyOutDir: true,
    assetsDir: 'assets',
  },
})
