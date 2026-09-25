create table public.inventory_batches (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  batch_number integer not null check (batch_number > 0),
  notes text,
  created_at timestamptz not null default now(),
  unique (user_id, batch_number)
);

create table public.inventory_batch_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  batch_id uuid not null references public.inventory_batches(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  unit_cost numeric(12,2) not null check (unit_cost >= 0),
  created_at timestamptz not null default now(),
  unique (batch_id, product_id)
);

alter table public.inventory_movements add column batch_id uuid references public.inventory_batches(id) on delete restrict;
alter table public.sales add column batch_id uuid references public.inventory_batches(id) on delete set null;

create index inventory_batches_user_number_idx on public.inventory_batches(user_id, batch_number desc);
create index inventory_batch_items_batch_idx on public.inventory_batch_items(batch_id);
create index inventory_movements_batch_idx on public.inventory_movements(batch_id);
create index sales_batch_idx on public.sales(batch_id, created_at desc);

alter table public.inventory_batches enable row level security;
alter table public.inventory_batch_items enable row level security;
create policy inventory_batches_select on public.inventory_batches for select to authenticated using ((select auth.uid()) = user_id);
create policy inventory_batch_items_select on public.inventory_batch_items for select to authenticated using ((select auth.uid()) = user_id);
grant select on public.inventory_batches, public.inventory_batch_items to authenticated;
revoke all on public.inventory_batches, public.inventory_batch_items from anon;

create function public.register_inventory_adjustment(p_product_id uuid,p_actual_quantity integer,p_notes text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_current integer; v_delta integer; v_movement uuid; v_cost numeric;
begin
  if v_user is null then raise exception 'Não autenticado'; end if;
  if p_actual_quantity < 0 then raise exception 'A quantidade real não pode ser negativa'; end if;
  select current_stock,unit_cost into v_current,v_cost from public.products where id=p_product_id and user_id=v_user for update;
  if not found then raise exception 'Produto não encontrado'; end if;
  v_delta := p_actual_quantity-v_current;
  if v_delta=0 then raise exception 'O estoque já possui essa quantidade'; end if;
  perform set_config('ystio.stock_write','on',true);
  update public.products set current_stock=p_actual_quantity where id=p_product_id;
  insert into public.inventory_movements(user_id,product_id,movement_type,quantity,unit_cost,reference_type,notes)
  values(v_user,p_product_id,case when v_delta>0 then 'positive_adjustment'::public.inventory_movement_type else 'negative_adjustment'::public.inventory_movement_type end,v_delta,v_cost,'stock_correction',nullif(trim(p_notes),'')) returning id into v_movement;
  return v_movement;
end; $$;

create function public.register_inventory_batch(p_items jsonb,p_notes text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_batch uuid; v_number integer; v_item jsonb; v_product public.products%rowtype; v_qty integer; v_cost numeric;
begin
  if v_user is null then raise exception 'Não autenticado'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'O lote precisa ter itens'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user::text,0));
  select coalesce(max(batch_number),0)+1 into v_number from public.inventory_batches where user_id=v_user;
  insert into public.inventory_batches(user_id,batch_number,notes) values(v_user,v_number,nullif(trim(p_notes),'')) returning id into v_batch;
  perform set_config('ystio.stock_write','on',true);
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::integer; v_cost := (v_item->>'unit_cost')::numeric;
    if v_qty<=0 or v_cost<0 then raise exception 'Quantidade ou custo inválido'; end if;
    select * into v_product from public.products where id=(v_item->>'product_id')::uuid and user_id=v_user and active=true for update;
    if not found then raise exception 'Produto indisponível'; end if;
    insert into public.inventory_batch_items(user_id,batch_id,product_id,quantity,unit_cost) values(v_user,v_batch,v_product.id,v_qty,v_cost);
    update public.products set current_stock=current_stock+v_qty,unit_cost=v_cost where id=v_product.id;
    insert into public.inventory_movements(user_id,product_id,movement_type,quantity,unit_cost,reference_type,reference_id,batch_id,notes)
    values(v_user,v_product.id,'entry',v_qty,v_cost,'inventory_batch',v_batch,v_batch,p_notes);
  end loop;
  return v_batch;
end; $$;

create or replace function public.register_sale(p_idempotency_key uuid,p_payment_method public.payment_method,p_received_amount numeric,p_items jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_sale uuid; v_batch uuid; v_total numeric(12,2):=0; v_item jsonb; v_product public.products%rowtype; v_qty integer;
begin
  if v_user is null then raise exception 'Não autenticado'; end if;
  if p_received_amount < 0 then raise exception 'Valor recebido inválido'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then raise exception 'A venda precisa ter itens'; end if;
  select id into v_sale from public.sales where user_id=v_user and idempotency_key=p_idempotency_key;
  if v_sale is not null then return v_sale; end if;
  select id into v_batch from public.inventory_batches where user_id=v_user order by batch_number desc limit 1;
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::integer;
    if v_qty <= 0 then raise exception 'Quantidade inválida'; end if;
    select * into v_product from public.products where id=(v_item->>'product_id')::uuid and user_id=v_user and active=true for update;
    if not found then raise exception 'Produto indisponível'; end if;
    if v_product.current_stock < v_qty then raise exception 'Estoque insuficiente para %',v_product.name; end if;
    v_total := v_total + v_product.sale_price*v_qty;
  end loop;
  insert into public.sales(user_id,idempotency_key,calculated_total,received_amount,payment_method,batch_id) values(v_user,p_idempotency_key,v_total,p_received_amount,p_payment_method,v_batch) returning id into v_sale;
  perform set_config('ystio.stock_write','on',true);
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::integer;
    select * into v_product from public.products where id=(v_item->>'product_id')::uuid and user_id=v_user for update;
    insert into public.sale_items(user_id,sale_id,product_id,product_name,quantity,unit_price,unit_cost) values(v_user,v_sale,v_product.id,v_product.name,v_qty,v_product.sale_price,v_product.unit_cost);
    update public.products set current_stock=current_stock-v_qty where id=v_product.id;
    insert into public.inventory_movements(user_id,product_id,movement_type,quantity,unit_cost,reference_type,reference_id,batch_id) values(v_user,v_product.id,'sale_out',-v_qty,v_product.unit_cost,'sale',v_sale,v_batch);
  end loop;
  return v_sale;
end; $$;

revoke all on function public.register_inventory_adjustment(uuid,integer,text) from public,anon;
revoke all on function public.register_inventory_batch(jsonb,text) from public,anon;
grant execute on function public.register_inventory_adjustment(uuid,integer,text) to authenticated;
grant execute on function public.register_inventory_batch(jsonb,text) to authenticated;
