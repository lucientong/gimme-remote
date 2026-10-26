import { defineConfig } from 'vite';
import preact from '@preact/preset-vite';

export default defineConfig({
  plugins: [preact()],
  server: {
    proxy: { '/ws': { target: 'ws://127.0.0.1:9271', ws: true, changeOrigin: true } },
  },
});
