import {defineConfig} from 'vite';
import {resolve} from 'node:path';
export default defineConfig({
  base:'./',
  build:{
    outDir:'../app/src/main/assets/effect-editor',
    emptyOutDir:true,
    assetsInlineLimit:0,
    rollupOptions:{
      input:{
        blocks:resolve(__dirname,'index.html'),
        script:resolve(__dirname,'script.html'),
      },
    },
  }
});
