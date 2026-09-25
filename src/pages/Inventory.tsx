import { FormEvent, useEffect, useMemo, useState, type ReactNode } from 'react';
import { AlertTriangle, ArrowDownToLine, Boxes, Link2, RefreshCw } from 'lucide-react';
import { Link, useNavigate } from 'react-router-dom';
import { Toast } from '../components/Toast';
import { getBatches, getMovements, getProducts, getSuppliers } from '../lib/data';
import { dateTime, money } from '../lib/format';
import { supabase } from '../lib/supabase';
import type { InventoryBatch, InventoryMovement, Product, Supplier } from '../types';
import { Top } from './Products';

type Mode = 'single' | 'batch' | 'adjust';
type Draft = { quantity: string; unit_cost: string };

export function Inventory() {
  const nav = useNavigate();
  const [products, setProducts] = useState<Product[]>([]);
  const [moves, setMoves] = useState<InventoryMovement[]>([]);
  const [batches, setBatches] = useState<InventoryBatch[]>([]);
  const [suppliers, setSuppliers] = useState<Supplier[]>([]);
  const [supplierId, setSupplierId] = useState('');
  const [mode, setMode] = useState<Mode>('single');
  const [selected, setSelected] = useState('');
  const [qty, setQty] = useState('');
  const [cost, setCost] = useState('');
  const [actual, setActual] = useState('');
  const [notes, setNotes] = useState('');
  const [lotId, setLotId] = useState('');
  const [lotQty, setLotQty] = useState('');
  const [draft, setDraft] = useState<Record<string, Draft>>({});
  const [msg, setMsg] = useState('');
  const [busy, setBusy] = useState(false);

  const load = () => Promise.all([getProducts(true), getMovements(), getBatches(), getSuppliers()]).then(([p, m, b, s]) => {
    setProducts(p); setMoves(m); setBatches(b); setSuppliers(s);
    setDraft(Object.fromEntries(p.map(x => [x.id, { quantity: '', unit_cost: String(x.unit_cost) }])));
  });
  useEffect(() => { void load(); }, []);

  function choose(id: string) {
    setSelected(id);
    const product = products.find(x => x.id === id);
    if (!product) return;
    setCost(String(product.unit_cost)); setActual(String(product.current_stock));
    const activeBatch = product.active_batch_id || '';
    setLotId(activeBatch);
    const item = batches.find(b => b.id === activeBatch)?.inventory_batch_items?.find(i => i.product_id === id);
    setLotQty(String(item?.quantity ?? product.current_stock));
  }

  async function run(action: () => PromiseLike<{ error: unknown }>, success: string) {
    setBusy(true); setMsg('');
    const { error } = await action(); setBusy(false);
    if (error) { setMsg(error instanceof Error ? error.message : String(error)); return; }
    setMsg(success); setQty(''); setActual(''); setNotes(''); setSelected(''); setLotId(''); setLotQty('');
    await load();
  }
  async function submitSingle(e: FormEvent) { e.preventDefault(); await run(() => supabase.rpc('register_inventory_entry', { p_product_id: selected, p_quantity: Number(qty), p_unit_cost: Number(cost), p_notes: notes || null }), 'Entrada registrada.'); }
  async function submitAdjust(e: FormEvent) { e.preventDefault(); await run(() => supabase.rpc('register_inventory_adjustment', { p_product_id: selected, p_actual_quantity: Number(actual), p_notes: notes }), 'Estoque corrigido com histórico preservado.'); }
  async function submitAssign(e: FormEvent) { e.preventDefault(); await run(() => supabase.rpc('assign_existing_stock_to_batch', { p_product_id: selected, p_batch_id: lotId, p_quantity: Number(lotQty), p_notes: notes || null }), 'Produto vinculado ao lote sem alterar o saldo.'); }
  async function submitBatch(e: FormEvent) {
    e.preventDefault();
    const items = products.filter(p => Number(draft[p.id]?.quantity) > 0).map(p => ({ product_id: p.id, quantity: Number(draft[p.id].quantity), unit_cost: Number(draft[p.id].unit_cost) }));
    if (!items.length) { setMsg('Informe a quantidade de pelo menos um produto.'); return; }
    setBusy(true); setMsg('');
    const { data, error } = await supabase.rpc('register_inventory_batch', { p_items: items, p_notes: notes || null });
    if (!error && supplierId && data) await supabase.from('inventory_batches').update({ supplier_id: supplierId }).eq('id', data);
    setBusy(false); if (error) setMsg(error.message); else { setMsg('Lote criado e estoque atualizado.'); setSupplierId(''); setNotes(''); await load(); }
  }

  const next = String((batches[0]?.batch_number || 0) + 1).padStart(4, '0');
  const investment = useMemo(() => products.reduce((n, p) => n + Number(draft[p.id]?.quantity || 0) * Number(draft[p.id]?.unit_cost || 0), 0), [products, draft]);

  return <div>
    <Top title="Estoque" back={() => nav(-1)} />
    <div className="mt-5 grid grid-cols-2 gap-3">{products.map(p => <div key={p.id} className="card p-4"><div className="flex items-start justify-between"><p className="font-bold">{p.name}</p>{p.minimum_stock != null && p.current_stock <= p.minimum_stock && <AlertTriangle size={18} className="text-amber-300" />}</div><p className="mt-3 text-3xl font-black">{p.current_stock}</p><p className="text-xs text-muted">unidades disponíveis</p></div>)}</div>
    <div className="mt-5 grid grid-cols-3 gap-2">{([['single', 'Avulso'], ['batch', 'Por lote'], ['adjust', 'Corrigir']] as const).map(([k, v]) => <button key={k} onClick={() => { setMode(k); setSelected(''); }} className={`chip ${mode === k ? 'chip-active' : ''}`}>{v}</button>)}</div>

    {mode === 'single' && <form onSubmit={submitSingle} className="card mt-4 space-y-4 p-5"><Title icon={<ArrowDownToLine size={20} />} text="Entrada avulsa" /><ProductSelect products={products} selected={selected} choose={choose} /><div className="grid grid-cols-2 gap-3"><Field label="Quantidade" value={qty} set={setQty} min="1" /><Field label="Custo unitário" value={cost} set={setCost} min="0" step="0.01" /></div><Notes value={notes} set={setNotes} /><button disabled={busy} className="btn-primary w-full">Confirmar entrada</button></form>}

    {mode === 'adjust' && <div className="space-y-4">
      <form onSubmit={submitAdjust} className="card mt-4 space-y-4 p-5"><Title icon={<RefreshCw size={20} />} text="Corrigir saldo" /><p className="text-sm text-muted">Informe a quantidade real. O Ystio registrará apenas a diferença como ajuste, sem apagar o histórico.</p><ProductSelect products={products} selected={selected} choose={choose} /><Field label="Quantidade real atual" value={actual} set={setActual} min="0" /><Notes value={notes} set={setNotes} required /><button disabled={busy} className="btn-primary w-full">Aplicar correção</button></form>
      <form onSubmit={submitAssign} className="card space-y-4 p-5"><Title icon={<Link2 size={20} />} text="Vincular estoque existente a um lote" /><p className="text-sm text-muted">Organiza as unidades que já estão no estoque. Esta ação não adiciona nem remove produtos.</p><ProductSelect products={products} selected={selected} choose={choose} /><label><span className="label">Lote</span><select className="input" required value={lotId} onChange={e => setLotId(e.target.value)}><option value="">Selecione o lote</option>{batches.map(b => <option key={b.id} value={b.id}>Lote {String(b.batch_number).padStart(4, '0')}</option>)}</select></label><Field label="Quantidade deste produto no lote" value={lotQty} set={setLotQty} min="0" /><Notes value={notes} set={setNotes} /><button disabled={busy || !batches.length} className="btn-primary w-full">Vincular ao lote</button>{!batches.length && <p className="text-xs text-amber-200">Crie primeiro um lote na opção “Por lote”.</p>}</form>
    </div>}

    {mode === 'batch' && <form onSubmit={submitBatch} className="card mt-4 space-y-4 p-5"><div className="flex items-center justify-between"><Title icon={<Boxes size={20} />} text={`Novo lote ${next}`} /><b className="text-cyan">{money(investment)}</b></div><p className="text-sm text-muted">Preencha somente os produtos que fazem parte deste lote.</p><label><span className="label">Fornecedor (opcional)</span><select className="input" value={supplierId} onChange={e=>setSupplierId(e.target.value)}><option value="">Não informado</option>{suppliers.map(s=><option key={s.id} value={s.id}>{s.name}</option>)}</select></label>{products.map(p => <div key={p.id} className="rounded-2xl border border-white/10 p-4"><p className="mb-3 font-bold">{p.name}</p><div className="grid grid-cols-2 gap-3"><Field label="Quantidade" value={draft[p.id]?.quantity || ''} set={v => setDraft(d => ({ ...d, [p.id]: { ...d[p.id], quantity: v } }))} min="0" required={false} /><Field label="Custo unitário" value={draft[p.id]?.unit_cost || ''} set={v => setDraft(d => ({ ...d, [p.id]: { ...d[p.id], unit_cost: v } }))} min="0" step="0.01" /></div></div>)}<Notes value={notes} set={setNotes} /><button disabled={busy} className="btn-primary w-full">Criar lote e adicionar estoque</button></form>}

    <div className="mb-3 mt-7 flex items-center justify-between"><h2 className="font-bold">Lotes</h2><Link className="text-sm text-electric" to="/reports">Ver relatório</Link></div>
    <div className="space-y-2">{batches.slice(0, 5).map(b => <div key={b.id} className="card p-4"><div className="flex justify-between"><b>Lote {String(b.batch_number).padStart(4, '0')}</b><span className="text-xs text-muted">{dateTime(b.created_at)}</span></div><p className="mt-2 text-sm text-muted">{b.inventory_batch_items?.map(i => `${i.products?.name} (${i.quantity})`).join(' · ')}</p></div>)}{!batches.length && <p className="text-sm text-muted">Nenhum lote cadastrado.</p>}</div>
    <div className="mb-3 mt-7 flex items-center justify-between"><h2 className="font-bold">Movimentações recentes</h2><Link className="text-sm text-electric" to="/products">Produtos</Link></div>
    <div className="space-y-2">{moves.map(m => <div key={m.id} className="card flex items-center p-4"><div className="flex-1"><p className="font-semibold">{m.products?.name}</p><p className="text-xs text-muted">{labels[m.movement_type]} · {dateTime(m.created_at)}</p></div><p className={`font-bold ${m.quantity > 0 ? 'text-cyan' : 'text-amber-200'}`}>{m.quantity > 0 ? '+' : ''}{m.quantity}</p></div>)}</div>
    {msg && <Toast message={msg} />}
  </div>;
}

function Title({ icon, text }: { icon: ReactNode; text: string }) { return <div className="flex items-center gap-2 font-bold text-cyan">{icon}<span className="text-white">{text}</span></div>; }
function ProductSelect({ products, selected, choose }: { products: Product[]; selected: string; choose: (id: string) => void }) { return <label><span className="label">Produto</span><select className="input" required value={selected} onChange={e => choose(e.target.value)}><option value="">Selecione</option>{products.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}</select></label>; }
function Field({ label, value, set, min, step = '1', required = true }: { label: string; value: string; set: (v: string) => void; min: string; step?: string; required?: boolean }) { return <label><span className="label">{label}</span><input className="input" required={required} type="number" min={min} step={step} value={value} onChange={e => set(e.target.value)} /></label>; }
function Notes({ value, set, required = false }: { value: string; set: (v: string) => void; required?: boolean }) { return <label><span className="label">Motivo/observação {required ? '' : '(opcional)'}</span><input className="input" required={required} value={value} onChange={e => set(e.target.value)} placeholder={required ? 'Ex.: contagem física corrigida' : 'Ex.: reposição semanal'} /></label>; }
const labels = { entry: 'Entrada', sale_out: 'Venda', positive_adjustment: 'Ajuste +', negative_adjustment: 'Ajuste −', sale_cancellation: 'Cancelamento' };
