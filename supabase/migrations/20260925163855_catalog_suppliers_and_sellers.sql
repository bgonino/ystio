create table public.product_categories (
  id uuid primary key default gen_random_uuid(), user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check(length(trim(name)) between 1 and 80), active boolean not null default true, created_at timestamptz not null default now(),
  unique(user_id,name)
);
create table public.suppliers (
  id uuid primary key default gen_random_uuid(), user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check(length(trim(name)) between 1 and 120), notes text, active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.sellers (
  id uuid primary key default gen_random_uuid(), user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check(length(trim(name)) between 1 and 80), is_primary boolean not null default false, active boolean not null default true,
  sort_order integer not null default 1 check(sort_order>0), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index sellers_one_primary_per_user on public.sellers(user_id) where is_primary;
create unique index sellers_user_order on public.sellers(user_id,sort_order);

alter table public.products add column category_id uuid references public.product_categories(id) on delete set null;
alter table public.inventory_batches add column supplier_id uuid references public.suppliers(id) on delete set null;
alter table public.sales add column seller_id uuid references public.sellers(id) on delete restrict;
alter table public.sale_items add column category_id uuid references public.product_categories(id) on delete set null,
  add column supplier_id uuid references public.suppliers(id) on delete set null,
  add column batch_id uuid references public.inventory_batches(id) on delete set null,
  add column category_name text, add column supplier_name text;
alter table public.inventory_movements add column seller_id uuid references public.sellers(id) on delete set null;

create table public.seller_inventory (
  user_id uuid not null references auth.users(id) on delete cascade, seller_id uuid not null references public.sellers(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict, quantity integer not null default 0 check(quantity>=0), updated_at timestamptz not null default now(),
  primary key(seller_id,product_id)
);
create table public.seller_stock_transfers (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  seller_id uuid not null references public.sellers(id) on delete restrict, product_id uuid not null references public.products(id) on delete restrict,
  direction text not null check(direction in('to_seller','to_central')), quantity integer not null check(quantity>0), notes text, created_at timestamptz not null default now()
);

do $$ declare u record; c uuid; s uuid; begin
  for u in select id from auth.users loop
    insert into public.product_categories(user_id,name) values(u.id,'Sem categoria') on conflict(user_id,name) do update set active=true returning id into c;
    update public.products set category_id=c where user_id=u.id and category_id is null;
    insert into public.sellers(user_id,name,is_primary,sort_order) values(u.id,'Vendedor principal',true,1)
      on conflict(user_id) where is_primary do update set name=excluded.name returning id into s;
    update public.sales set seller_id=s where user_id=u.id and seller_id is null;
  end loop;
end $$;
update public.sale_items si set category_id=p.category_id,category_name=c.name,batch_id=s.batch_id,supplier_id=b.supplier_id,supplier_name=sp.name
from public.products p left join public.product_categories c on c.id=p.category_id, public.sales s
left join public.inventory_batches b on b.id=s.batch_id left join public.suppliers sp on sp.id=b.supplier_id
where si.product_id=p.id and si.sale_id=s.id;

alter table public.product_categories enable row level security; alter table public.suppliers enable row level security; alter table public.sellers enable row level security;
alter table public.seller_inventory enable row level security; alter table public.seller_stock_transfers enable row level security;
create policy categories_all on public.product_categories for all to authenticated using((select auth.uid())=user_id) with check((select auth.uid())=user_id);
create policy suppliers_all on public.suppliers for all to authenticated using((select auth.uid())=user_id) with check((select auth.uid())=user_id);
create policy sellers_all on public.sellers for all to authenticated using((select auth.uid())=user_id) with check((select auth.uid())=user_id);
create policy seller_inventory_select on public.seller_inventory for select to authenticated using((select auth.uid())=user_id);
create policy seller_transfers_select on public.seller_stock_transfers for select to authenticated using((select auth.uid())=user_id);
create policy inventory_batches_update on public.inventory_batches for update to authenticated using((select auth.uid())=user_id) with check((select auth.uid())=user_id);
grant select,insert,update on public.product_categories,public.suppliers,public.sellers to authenticated;
grant select on public.seller_inventory,public.seller_stock_transfers to authenticated;
grant update on public.inventory_batches to authenticated;
revoke all on public.product_categories,public.suppliers,public.sellers,public.seller_inventory,public.seller_stock_transfers from anon;

create function public.ensure_user_defaults() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); c uuid; s uuid; begin
 if u is null then raise exception 'Não autenticado'; end if;
 insert into public.product_categories(user_id,name) values(u,'Sem categoria') on conflict(user_id,name) do update set active=true returning id into c;
 insert into public.sellers(user_id,name,is_primary,sort_order) values(u,'Vendedor principal',true,1) on conflict(user_id) where is_primary do update set active=true returning id into s;
 update public.products set category_id=c where user_id=u and category_id is null; update public.sales set seller_id=s where user_id=u and seller_id is null;
 return jsonb_build_object('category_id',c,'seller_id',s); end; $$;

create function public.transfer_seller_stock(p_seller_id uuid,p_product_id uuid,p_quantity integer,p_direction text,p_notes text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); p public.products%rowtype; q integer; t uuid; primary_seller boolean;
begin if u is null then raise exception 'Não autenticado'; end if; if p_quantity<=0 or p_direction not in('to_seller','to_central') then raise exception 'Transferência inválida'; end if;
 select is_primary into primary_seller from public.sellers where id=p_seller_id and user_id=u and active; if not found or primary_seller then raise exception 'Selecione um vendedor adicional'; end if;
 select * into p from public.products where id=p_product_id and user_id=u for update; if not found then raise exception 'Produto não encontrado'; end if;
 select quantity into q from public.seller_inventory where seller_id=p_seller_id and product_id=p_product_id for update; q:=coalesce(q,0);
 if p_direction='to_seller' then if p.current_stock<p_quantity then raise exception 'Estoque central insuficiente'; end if; perform set_config('ystio.stock_write','on',true); update public.products set current_stock=current_stock-p_quantity where id=p_product_id; q:=q+p_quantity;
 else if q<p_quantity then raise exception 'Estoque do vendedor insuficiente'; end if; perform set_config('ystio.stock_write','on',true); update public.products set current_stock=current_stock+p_quantity where id=p_product_id; q:=q-p_quantity; end if;
 insert into public.seller_inventory(user_id,seller_id,product_id,quantity) values(u,p_seller_id,p_product_id,q) on conflict(seller_id,product_id) do update set quantity=excluded.quantity,updated_at=now();
 insert into public.seller_stock_transfers(user_id,seller_id,product_id,direction,quantity,notes) values(u,p_seller_id,p_product_id,p_direction,p_quantity,nullif(trim(p_notes),'')) returning id into t; return t; end; $$;

drop function public.register_sale(uuid,public.payment_method,numeric,jsonb);
create function public.register_sale(p_idempotency_key uuid,p_payment_method public.payment_method,p_received_amount numeric,p_items jsonb,p_seller_id uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); sid uuid; primary_seller boolean; saleid uuid; batchid uuid; candidate uuid; total numeric(12,2):=0; item jsonb; p public.products%rowtype; qty integer; available integer; first_item boolean:=true; cname text; suppid uuid; suppname text;
begin if u is null then raise exception 'Não autenticado'; end if; if p_received_amount<0 then raise exception 'Valor recebido inválido'; end if;
 select id into saleid from public.sales where user_id=u and idempotency_key=p_idempotency_key; if saleid is not null then return saleid; end if;
 if p_seller_id is null then select id,is_primary into sid,primary_seller from public.sellers where user_id=u and is_primary; else select id,is_primary into sid,primary_seller from public.sellers where id=p_seller_id and user_id=u and active; end if; if sid is null then raise exception 'Vendedor inválido'; end if;
 for item in select * from jsonb_array_elements(p_items) loop qty:=(item->>'quantity')::integer; if qty<=0 then raise exception 'Quantidade inválida'; end if;
  select * into p from public.products where id=(item->>'product_id')::uuid and user_id=u and active for update; if not found then raise exception 'Produto indisponível'; end if;
  if primary_seller then available:=p.current_stock; else select quantity into available from public.seller_inventory where seller_id=sid and product_id=p.id for update; available:=coalesce(available,0); end if;
  if available<qty then raise exception 'Estoque insuficiente para %',p.name; end if; total:=total+p.sale_price*qty; candidate:=p.active_batch_id;
  if first_item then batchid:=candidate;first_item:=false;elsif batchid is distinct from candidate then batchid:=null;end if;
 end loop;
 insert into public.sales(user_id,idempotency_key,calculated_total,received_amount,payment_method,batch_id,seller_id) values(u,p_idempotency_key,total,p_received_amount,p_payment_method,batchid,sid) returning id into saleid;
 perform set_config('ystio.stock_write','on',true);
 for item in select * from jsonb_array_elements(p_items) loop qty:=(item->>'quantity')::integer; select * into p from public.products where id=(item->>'product_id')::uuid and user_id=u for update;
  select name into cname from public.product_categories where id=p.category_id; select b.supplier_id,s.name into suppid,suppname from public.inventory_batches b left join public.suppliers s on s.id=b.supplier_id where b.id=p.active_batch_id;
  insert into public.sale_items(user_id,sale_id,product_id,product_name,quantity,unit_price,unit_cost,category_id,category_name,supplier_id,supplier_name,batch_id) values(u,saleid,p.id,p.name,qty,p.sale_price,p.unit_cost,p.category_id,cname,suppid,suppname,p.active_batch_id);
  if primary_seller then update public.products set current_stock=current_stock-qty where id=p.id; else update public.seller_inventory set quantity=quantity-qty,updated_at=now() where seller_id=sid and product_id=p.id; end if;
  insert into public.inventory_movements(user_id,product_id,movement_type,quantity,unit_cost,reference_type,reference_id,batch_id,seller_id) values(u,p.id,'sale_out',-qty,p.unit_cost,'sale',saleid,p.active_batch_id,sid);
 end loop; return saleid; end; $$;

create or replace function public.cancel_sale(p_sale_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); s public.sales%rowtype; i public.sale_items%rowtype; primary_seller boolean;
begin if u is null then raise exception 'Não autenticado'; end if; select * into s from public.sales where id=p_sale_id and user_id=u for update; if not found then raise exception 'Venda não encontrada'; end if; if s.status='cancelled' then return; end if;
 select is_primary into primary_seller from public.sellers where id=s.seller_id; perform set_config('ystio.stock_write','on',true);
 for i in select * from public.sale_items where sale_id=p_sale_id loop
  if coalesce(primary_seller,true) then update public.products set current_stock=current_stock+i.quantity where id=i.product_id and user_id=u; else insert into public.seller_inventory(user_id,seller_id,product_id,quantity) values(u,s.seller_id,i.product_id,i.quantity) on conflict(seller_id,product_id) do update set quantity=public.seller_inventory.quantity+excluded.quantity,updated_at=now(); end if;
  insert into public.inventory_movements(user_id,product_id,movement_type,quantity,unit_cost,reference_type,reference_id,batch_id,seller_id,notes) values(u,i.product_id,'sale_cancellation',i.quantity,i.unit_cost,'sale',p_sale_id,i.batch_id,s.seller_id,'Restituição por cancelamento');
 end loop; update public.sales set status='cancelled',cancelled_at=now() where id=p_sale_id; end; $$;

revoke all on function public.ensure_user_defaults() from public,anon; revoke all on function public.transfer_seller_stock(uuid,uuid,integer,text,text) from public,anon;
revoke all on function public.register_sale(uuid,public.payment_method,numeric,jsonb,uuid) from public,anon;
grant execute on function public.ensure_user_defaults(),public.transfer_seller_stock(uuid,uuid,integer,text,text),public.register_sale(uuid,public.payment_method,numeric,jsonb,uuid) to authenticated;
