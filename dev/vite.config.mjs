import { mergeConfig } from '/app/node_modules/vite/dist/node/index.js';
import base from '/app/vite.config.js';
export default mergeConfig(base, {
  server: {
    strictPort: true,
    allowedHosts: ['localhost'],
    proxy: {
      '/api': { target: 'http://backend:3001', rewrite: path => path.replace(/^\/api(?=\/|$)/, '') },
    },
  },
});
