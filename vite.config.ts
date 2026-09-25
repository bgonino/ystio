import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  plugins: [react(), VitePWA({
    registerType: 'autoUpdate',
    injectRegister: 'auto',
    includeAssets: ['icons/ystio-mark.png'],
    manifest: { name:'Ystio', short_name:'Ystio', description:'Vendas, estoque e resultados.', theme_color:'#061526', background_color:'#061526', display:'standalone', start_url:'/', scope:'/', orientation:'portrait-primary', icons:[{src:'/icons/ystio-mark.png',sizes:'any',type:'image/png',purpose:'any'}] },
    workbox: { navigateFallback:'/index.html', globPatterns:['**/*.{js,css,html,svg,woff2}'] }
  })]
})
