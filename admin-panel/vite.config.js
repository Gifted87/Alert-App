import { defineConfig } from 'vite';

export default defineConfig({
  build: {
    rollupOptions: {
      output: {
        manualChunks: {
          'firebase-app': ['@firebase/app'],
          'firebase-auth': ['@firebase/auth'],
          'firebase-firestore': ['@firebase/firestore'],
        },
      },
    },
  },
});
