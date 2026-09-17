# Ystio

Aplicativo mobile-first para registrar vendas, controlar estoque e acompanhar resultados com velocidade.

## Stack

React, TypeScript, Vite, Tailwind CSS, Supabase e PWA. A aplicação é estática e preparada para Cloudflare Pages.

## Desenvolvimento

1. Copie `.env.example` para `.env.local` e preencha somente a URL e a chave pública do Supabase.
2. Execute `pnpm install`.
3. Execute `pnpm dev`.

Validações: `pnpm lint`, `pnpm test` e `pnpm build`.

## Banco de dados

As migrations ficam em `supabase/migrations`. As funções `register_sale`, `register_inventory_entry` e `cancel_sale` executam operações atômicas no PostgreSQL. Todas as tabelas públicas usam RLS por proprietário; o frontend nunca usa `service_role`.

## Deploy

Cloudflare Pages: build `pnpm build`, saída `dist`, branch `main`. Configure `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY` como variáveis de build. O arquivo `public/_redirects` mantém as rotas da SPA funcionais.

## Escopo V1

- login por e-mail e senha e sessão persistente;
- produtos genéricos e entrada de estoque;
- venda de múltiplos itens, PIX/dinheiro, valor recebido e troco;
- baixa transacional, proteção contra toque duplo e estoque insuficiente;
- cancelamento com movimentação compensatória;
- dashboard, histórico e relatórios de faturamento, custo e lucro bruto;
- PWA instalável e interface mobile dark premium.
