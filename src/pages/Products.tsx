import { FormEvent, useEffect, useMemo, useState } from 'react'
import { ChevronLeft, Pencil, Plus, Power } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { Toast } from '../components/Toast'
import { getBatches, getCategories, getProducts, getSuppliers } from '../lib/data'
import { money } from '../lib/format'
import { supabase } from '../lib/supabase'
import type { Category, InventoryBatch, Product, Supplier } from '../types'

const blank = { name: '', description: '', unit_cost: '', sale_price: '', minimum_stock: '', category_id: '', supplier_id: '', active_batch_id: '' }

export function Products() {
  const nav = useNavigate()
  const [items, setItems] = useState<Product[]>([])
  const [categories, setCategories] = useState<Category[]>([])
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [batches, setBatches] = useState<InventoryBatch[]>([])
  const [form, setForm] = useState(blank)
  const [editing, setEditing] = useState<Product | null>(null)
  const [open, setOpen] = useState(false)
  const [msg, setMsg] = useState('')
  const [busy, setBusy] = useState(false)
  const load = () => Promise.all([getProducts(), getCategories(), getSuppliers(), getBatches()]).then(([p, c, s, b]) => { setItems(p); setCategories(c); setSuppliers(s); setBatches(b) })
  useEffect(() => { void load() }, [])
  const availableBatches = useMemo(() => batches, [batches])

  function edit(product: Product) {
    const batch = batches.find(b => b.id === product.active_batch_id)
    setEditing(product)
    setForm({ name: product.name, description: product.description || '', unit_cost: String(product.unit_cost), sale_price: String(product.sale_price), minimum_stock: product.minimum_stock == null ? '' : String(product.minimum_stock), category_id: product.category_id || '', supplier_id: batch?.supplier_id || '', active_batch_id: product.active_batch_id || '' })
    setOpen(true)
  }

  async function save(e: FormEvent) {
    e.preventDefault(); setBusy(true); setMsg('')
    const payload = { name: form.name.trim(), description: form.description.trim() || null, unit_cost: Number(form.unit_cost), sale_price: Number(form.sale_price), minimum_stock: form.minimum_stock === '' ? null : Number(form.minimum_stock), category_id: form.category_id || categories[0]?.id || null }
    let productId = editing?.id
    let error: { message: string } | null = null
    if (editing) ({ error } = await supabase.from('products').update(payload).eq('id', editing.id))
    else { const result = await supabase.from('products').insert(payload).select('id').single(); productId = result.data?.id; error = result.error }
    if (!error && productId && form.active_batch_id !== (editing?.active_batch_id || '')) {
      if (form.active_batch_id) { const result = await supabase.rpc('link_product_batch', { p_product_id: productId, p_batch_id: form.active_batch_id === 'new' ? null : form.active_batch_id, p_supplier_id: form.supplier_id || null }); error = result.error }
      else { const result = await supabase.from('products').update({ active_batch_id: form.active_batch_id || null }).eq('id', productId); error = result.error }
    }
    setBusy(false)
    if (error) { setMsg(error.message); return }
    setMsg(editing ? 'Produto, lote e fornecedor atualizados.' : 'Produto criado.')
    setOpen(false); setEditing(null); setForm(blank); await load()
  }

  async function toggle(product: Product) { await supabase.from('products').update({ active: !product.active }).eq('id', product.id); await load() }

  return <div>
    <Top title="Produtos" back={() => nav(-1)} action={() => { setEditing(null); setForm(blank); setOpen(true) }} />
    <p className="mt-2 text-sm text-muted">Cadastre e organize os itens por categoria, fornecedor e lote.</p>
    {open && <form onSubmit={save} className="card mt-5 space-y-4 p-5">
      <label><span className="label">Nome</span><input className="input" required value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} placeholder="Ex.: Brigadeiro" /></label>
      <label><span className="label">Categoria</span><select className="input" value={form.category_id} onChange={e => setForm({ ...form, category_id: e.target.value })}><option value="">Sem categoria</option>{categories.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
      <div className="grid grid-cols-2 gap-3">
        <label><span className="label">Fornecedor</span><select className="input" value={form.supplier_id} onChange={e => setForm({ ...form, supplier_id: e.target.value, active_batch_id: batches.find(b => b.id === form.active_batch_id)?.supplier_id === e.target.value ? form.active_batch_id : '' })}><option value="">Não informado</option>{suppliers.filter(s => s.active).map(s => <option key={s.id} value={s.id}>{s.name}</option>)}</select></label>
        <label><span className="label">Lote atual</span><select className="input" value={form.active_batch_id} onChange={e => { const batch = batches.find(b => b.id === e.target.value); setForm({ ...form, active_batch_id: e.target.value, supplier_id: batch?.supplier_id || form.supplier_id }) }}><option value="">Sem lote</option><option value="new">Criar lote com este estoque</option>{availableBatches.map(b => <option key={b.id} value={b.id}>Lote {String(b.batch_number).padStart(4, '0')}</option>)}</select></label>
      </div>
      <p className="-mt-2 text-xs text-muted">O fornecedor pertence ao lote selecionado. Ao alterar, o estoque atual será vinculado ao novo lote sem criar uma entrada.</p>
      <label><span className="label">Descrição (opcional)</span><input className="input" value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} /></label>
      <div className="grid grid-cols-2 gap-3"><label><span className="label">Custo unitário</span><input className="input" type="number" min="0" step="0.01" required value={form.unit_cost} onChange={e => setForm({ ...form, unit_cost: e.target.value })} /></label><label><span className="label">Preço de venda</span><input className="input" type="number" min="0" step="0.01" required value={form.sale_price} onChange={e => setForm({ ...form, sale_price: e.target.value })} /></label></div>
      <label><span className="label">Estoque mínimo (opcional)</span><input className="input" type="number" min="0" step="1" value={form.minimum_stock} onChange={e => setForm({ ...form, minimum_stock: e.target.value })} /></label>
      <div className="flex gap-2"><button disabled={busy} className="btn-primary flex-1">{busy ? 'Salvando...' : 'Salvar'}</button><button type="button" className="btn-secondary" onClick={() => setOpen(false)}>Cancelar</button></div>
    </form>}
    <div className="mt-5 space-y-2">{items.map(product => { const batch = batches.find(b => b.id === product.active_batch_id); return <div key={product.id} className={`card flex items-center gap-3 p-4 ${!product.active ? 'opacity-55' : ''}`}><div className="min-w-0 flex-1"><p className="font-bold">{product.name}</p><p className="text-xs text-cyan">{product.product_categories?.name || 'Sem categoria'}{batch ? ` · Lote ${String(batch.batch_number).padStart(4, '0')}` : ''}</p><p className="mt-1 text-sm text-muted">{money(product.sale_price)} · Estoque {product.current_stock}{batch?.suppliers?.name ? ` · ${batch.suppliers.name}` : ''}</p></div><button onClick={() => edit(product)} className="grid h-10 w-10 place-items-center rounded-xl bg-white/[.05]" aria-label="Editar"><Pencil size={18} /></button><button onClick={() => toggle(product)} className="grid h-10 w-10 place-items-center rounded-xl bg-white/[.05]" aria-label="Ativar ou inativar"><Power size={18} /></button></div> })}{!items.length && <div className="card p-6 text-center text-muted">Cadastre seu primeiro produto.</div>}</div>
    {msg && <Toast message={msg} />}
  </div>
}

export function Top({ title, back, action }: { title: string; back: () => void; action?: () => void }) { return <div className="flex items-center gap-3"><button onClick={back} className="grid h-11 w-11 place-items-center rounded-xl bg-white/[.05]"><ChevronLeft /></button><h1 className="page-title flex-1">{title}</h1>{action && <button onClick={action} className="grid h-11 w-11 place-items-center rounded-xl bg-electric"><Plus /></button>}</div> }
