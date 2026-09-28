import { FormEvent, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { InventoryBatch, Product, Supplier } from '../types'

export function LinkStockBatch({ products, batches, suppliers, reload }: { products: Product[]; batches: InventoryBatch[]; suppliers: Supplier[]; reload: () => Promise<void> }) {
  const [productId, setProductId] = useState('')
  const [batchId, setBatchId] = useState('new')
  const [supplierId, setSupplierId] = useState('')
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  const [failed, setFailed] = useState(false)
  const product = products.find(p => p.id === productId)

  async function submit(e: FormEvent) {
    e.preventDefault()
    if (busy || !productId) return
    setBusy(true); setMessage(''); setFailed(false)
    try {
      const { data, error } = await supabase.rpc('link_product_batch', {
        p_product_id: productId,
        p_batch_id: batchId === 'new' ? null : batchId,
        p_supplier_id: batchId === 'new' ? supplierId || null : null
      })
      if (error) throw error
      setBatchId(data)
      setMessage('Estoque vinculado! A quantidade disponível foi preservada. Você pode selecionar outro produto para incluir no mesmo lote.')
      setProductId('')
      await reload()
    } catch (error) {
      setFailed(true)
      setMessage(error && typeof error === 'object' && 'message' in error ? String(error.message) : 'Não foi possível concluir. Verifique sua conexão e tente novamente.')
    } finally { setBusy(false) }
  }

  return <form onSubmit={submit} className="card mt-4 space-y-4 p-5">
    <h2 className="font-bold">Vincular estoque existente</h2>
    <p className="text-sm text-muted">Escolha um produto e organize todo o seu saldo atual em um lote. Isso não registra uma compra nem aumenta o estoque.</p>
    <label><span className="label">Produto cadastrado</span><select className="input" required disabled={busy} value={productId} onChange={e => setProductId(e.target.value)}><option value="">Selecione o produto</option>{products.map(p => <option key={p.id} value={p.id}>{p.name} · {p.current_stock} unidades</option>)}</select></label>
    <label><span className="label">Lote de destino</span><select className="input" required disabled={busy} value={batchId} onChange={e => setBatchId(e.target.value)}><option value="new">Criar novo lote com este estoque</option>{batches.map(b => <option key={b.id} value={b.id}>Lote {String(b.batch_number).padStart(4, '0')}{b.suppliers?.name ? ' · ' + b.suppliers.name : ''}</option>)}</select></label>
    {batchId === 'new' && <label><span className="label">Fornecedor do novo lote (opcional)</span><select className="input" disabled={busy} value={supplierId} onChange={e => setSupplierId(e.target.value)}><option value="">Não informado</option>{suppliers.filter(s => s.active).map(s => <option key={s.id} value={s.id}>{s.name}</option>)}</select></label>}
    {product && <p className="text-sm text-cyan">Serão vinculadas {product.current_stock} unidades de {product.name}. O saldo total continuará igual.</p>}
    <button className="btn-primary w-full" disabled={busy || !productId}>{busy ? 'Vinculando...' : batchId === 'new' ? 'Criar lote e vincular estoque' : 'Vincular ao lote'}</button>
    {message && <p role={failed ? 'alert' : 'status'} className={failed ? 'text-sm text-red-300' : 'text-sm text-cyan'}>{message}</p>}
  </form>
}
