import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  plugins: [react(), VitePWA({
    registerType: 'autoUpdate',
    injectRegister: false,
    includeAssets: ['favicon.svg','icons/icon-192.svg','icons/icon-512.svg'],
    manifest: { name:'Ystio', short_name:'Ystio', description:'Vendas, estoque e resultados.', theme_color:'#07111f', background_color:'#07111f', display:'standalone', start_url:'/', scope:'/', orientation:'portrait-primary', icons:[{src:'/icons/icon-192.svg',sizes:'192x192',type:'image/svg+xml',purpose:'any maskable'},{src:'/icons/icon-512.svg',sizes:'512x512',type:'image/svg+xml',purpose:'any maskable'}] },
    workbox: { navigateFallback:'/index.html', globPatterns:['**/*.{js,css,html,svg,woff2}'] }
  })]
})
