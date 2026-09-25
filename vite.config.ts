import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  plugins: [react(), VitePWA({
    registerType: 'autoUpdate',
    injectRegister: 'auto',
    includeAssets: ['icons/ystio-logo-mark.svg', 'icons/ystio-icon-192.png', 'icons/ystio-icon-512.png', 'icons/ystio-maskable-512.png', 'icons/apple-touch-icon.png'],
    manifest: { name:'Ystio', short_name:'Ystio', description:'Vendas, estoque e resultados.', theme_color:'#061526', background_color:'#061526', display:'standalone', start_url:'/', scope:'/', orientation:'portrait-primary', icons:[{src:'/icons/ystio-icon-192.png',sizes:'192x192',type:'image/png',purpose:'any'},{src:'/icons/ystio-icon-512.png',sizes:'512x512',type:'image/png',purpose:'any'},{src:'/icons/ystio-maskable-512.png',sizes:'512x512',type:'image/png',purpose:'maskable'}] },
    workbox: { navigateFallback:'/index.html', globPatterns:['**/*.{js,css,html,svg,png,woff2}'] }
  })]
})
