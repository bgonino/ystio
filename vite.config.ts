import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  plugins: [react(), VitePWA({
    registerType: 'autoUpdate',
    injectRegister: 'auto',
    includeAssets: ['icons/ystio-official.svg'],
    manifest: { name:'Ystio', short_name:'Ystio', description:'Vendas, estoque e resultados.', theme_color:'#061526', background_color:'#061526', display:'standalone', start_url:'/', scope:'/', orientation:'portrait-primary', icons:[{src:'/icons/ystio-official.svg',sizes:'any',type:'image/svg+xml',purpose:'any maskable'}] },
    workbox: { navigateFallback:'/index.html', globPatterns:['**/*.{js,css,html,svg,woff2}'] }
  })]
})
