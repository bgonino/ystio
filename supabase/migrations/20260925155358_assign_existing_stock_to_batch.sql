alter table public.products add column active_batch_id uuid references public.inventory_batches(id) on delete set null;
create index products_active_batch_idx on public.products(active_batch_id);

create table public.inventory_batch_assignments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  batch_id uuid not null references public.inventory_batches(id) on delete restrict,
  previous_quantity integer not null check (previous_quantity >= 0),
  assigned_quantity integer not null check (assigned_quantity >= 0),
  notes text,
  created_at timestamptz not null default now()
);
create index inventory_batch_assignments_user_created_idx on public.inventory_batch_assignments(user_id,created_at desc);
alter table public.inventory_batch_assignments enable row level security;
create policy inventory_batch_assignments_select on public.inventory_batch_assignments for select to authenticated using ((select auth.uid())=user_id);
grant select on public.inventory_batch_assignments to authenticated;
revoke all on public.inventory_batch_assignments from anon;

create function public.assign_existing_stock_to_batch(p_product_id uuid,p_batch_id uuid,p_quantity integer,p_notes text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid(); v_stock integer; v_cost numeric; v_batch_owner uuid; v_previous integer:=0; v_other integer; v_assignment uuid;
begin
  if v_user is null then raise exception 'Não autenticado'; end if;
  if p_quantity<0 then raise exception 'Quantidade inválida'; end if;
  select current_stock,unit_cost into v_stock,v_cost from public.products where id=p_product_id and user_id=v_user for update;
  if not found then raise exception 'Produto não encontrado'; end if;
  select user_id into v_batch_owner from public.inventory_batches where id=p_batch_id;
  if v_batch_owner is null or v_batch_owner<>v_user then raise exception 'Lote não encontrado'; end if;
  select coalesce(quantity,0) into v_previous from public.inventory_batch_items where batch_id=p_batch_id and product_id=p_product_id for update;
  v_previous:=coalesce(v_previous,0);
  select coalesce(sum(quantity),0) into v_other from public.inventory_batch_items where product_id=p_product_id and user_id=v_user and batch_id<>p_batch_id;
  if v_other+p_quantity>v_stock then raise exception 'A soma vinculada aos lotes não pode superar o estoque atual (%)',v_stock; end if;
  if p_quantity=0 then
    delete from public.inventory_batch_items where batch_id=p_batch_id and product_id=p_product_id;
  else
    insert into public.inventory_batch_items(user_id,batch_id,product_id,quantity,unit_cost)
    values(v_user,p_batch_id,p_product_id,p_quantity,v_cost)
    on conflict(batch_id,product_id) do update set quantity=excluded.quantity,unit_cost=excluded.unit_cost;
  end if;
  update public.products set active_batch_id=case when p_quantity>0 then p_batch_id else null end where id=p_product_id;
  insert into public.inventory_batch_assignments(user_id,product_id,batch_id,previous_quantity,assigned_quantity,notes)
  values(v_user,p_product_id,p_batch_id,v_previous,p_quantity,nullif(trim(p_notes),'')) returning id into v_assignment;
  return v_assignment;
end; $$;

create or replace function public.register_inventory_batch(p_items jsonb,p_notes text default null)
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
    update public.products set current_stock=current_stock+v_qty,unit_cost=v_cost,active_batch_id=v_batch where id=v_product.id;
    insert into public.inventory_movements(user_id,product_id,movement_type,quantity,unit_cost,reference_type,reference_id,batch_id,notes)
    values(v_user,v_product.id,'entry',v_qty,v_cost,'inventory_batch',v_batch,v_batch,p_notes);
  end loop;
  return v_batch;
end; $$;

create or replace function public.register_sale(p_idempotency_key uuid,p_payment_method public.payment_method,p_received_amount numeric,p_items jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_sale uuid; v_batch uuid; v_candidate uuid; v_total numeric(12,2):=0; v_item jsonb; v_product public.products%rowtype; v_qty integer; v_first boolean:=true;
begin
  if v_user is null then raise exception 'Não autenticado'; end if;
  if p_received_amount < 0 then raise exception 'Valor recebido inválido'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then raise exception 'A venda precisa ter itens'; end if;
  select id into v_sale from public.sales where user_id=v_user and idempotency_key=p_idempotency_key;
  if v_sale is not null then return v_sale; end if;
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::integer;
    if v_qty <= 0 then raise exception 'Quantidade inválida'; end if;
    select * into v_product from public.products where id=(v_item->>'product_id')::uuid and user_id=v_user and active=true for update;
    if not found then raise exception 'Produto indisponível'; end if;
    if v_product.current_stock < v_qty then raise exception 'Estoque insuficiente para %',v_product.name; end if;
    v_total := v_total + v_product.sale_price*v_qty; v_candidate:=v_product.active_batch_id;
    if v_first then v_batch:=v_candidate; v_first:=false; elsif v_batch is distinct from v_candidate then v_batch:=null; end if;
  end loop;
  insert into public.sales(user_id,idempotency_key,calculated_total,received_amount,payment_method,batch_id) values(v_user,p_idempotency_key,v_total,p_received_amount,p_payment_method,v_batch) returning id into v_sale;
  perform set_config('ystio.stock_write','on',true);
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::integer;
    select * into v_product from public.products where id=(v_item->>'product_id')::uuid and user_id=v_user for update;
    insert into public.sale_items(user_id,sale_id,product_id,product_name,quantity,unit_price,unit_cost) values(v_user,v_sale,v_product.id,v_product.name,v_qty,v_product.sale_price,v_product.unit_cost);
    update public.products set current_stock=current_stock-v_qty where id=v_product.id;
    insert into public.inventory_movements(user_id,product_id,movement_type,quantity,unit_cost,reference_type,reference_id,batch_id) values(v_user,v_product.id,'sale_out',-v_qty,v_product.unit_cost,'sale',v_sale,v_product.active_batch_id);
  end loop;
  return v_sale;
end; $$;

revoke all on function public.assign_existing_stock_to_batch(uuid,uuid,integer,text) from public,anon;
grant execute on function public.assign_existing_stock_to_batch(uuid,uuid,integer,text) to authenticated;
