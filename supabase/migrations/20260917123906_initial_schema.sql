create extension if not exists pgcrypto;

create type public.payment_method as enum ('pix','cash');
create type public.sale_status as enum ('completed','cancelled');
create type public.inventory_movement_type as enum ('entry','sale_out','positive_adjustment','negative_adjustment','sale_cancellation');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 120),
  description text,
  unit_cost numeric(12,2) not null default 0 check (unit_cost >= 0),
  sale_price numeric(12,2) not null default 0 check (sale_price >= 0),
  current_stock integer not null default 0 check (current_stock >= 0),
  minimum_stock integer check (minimum_stock is null or minimum_stock >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, name)
);

create table public.sales (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  idempotency_key uuid not null,
  calculated_total numeric(12,2) not null check (calculated_total >= 0),
  received_amount numeric(12,2) not null check (received_amount >= 0),
  payment_method public.payment_method not null,
  status public.sale_status not null default 'completed',
  created_at timestamptz not null default now(),
  cancelled_at timestamptz,
  unique (user_id, idempotency_key)
);

create table public.sale_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  sale_id uuid not null references public.sales(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  product_name text not null,
  quantity integer not null check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  unit_cost numeric(12,2) not null check (unit_cost >= 0),
  subtotal numeric(12,2) generated always as (quantity * unit_price) stored,
  created_at timestamptz not null default now()
);

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  movement_type public.inventory_movement_type not null,
  quantity integer not null check (quantity <> 0),
  unit_cost numeric(12,2) check (unit_cost is null or unit_cost >= 0),
  reference_type text,
  reference_id uuid,
  notes text,
  created_at timestamptz not null default now(),
  check ((movement_type in ('entry','positive_adjustment','sale_cancellation') and quantity > 0) or (movement_type in ('sale_out','negative_adjustment') and quantity < 0))
);

create index products_user_active_idx on public.products(user_id, active);
create index sales_user_created_idx on public.sales(user_id, created_at desc);
create index sales_user_status_idx on public.sales(user_id, status);
create index sale_items_sale_idx on public.sale_items(sale_id);
create index sale_items_product_idx on public.sale_items(product_id);
create index inventory_user_created_idx on public.inventory_movements(user_id, created_at desc);
create index inventory_product_idx on public.inventory_movements(product_id, created_at desc);

create function public.set_updated_at() returns trigger language plpgsql security invoker set search_path = '' as $$
begin new.updated_at = now(); return new; end; $$;
create trigger profiles_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger products_updated_at before update on public.products for each row execute function public.set_updated_at();

create function public.handle_new_user() returns trigger language plpgsql security definer set search_path = '' as $$
begin insert into public.profiles(id,full_name) values(new.id,coalesce(new.raw_user_meta_data->>'full_name','Bruno')); return new; end; $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.inventory_movements enable row level security;

create policy profiles_select on public.profiles for select to authenticated using ((select auth.uid()) = id);
create policy profiles_update on public.profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create policy products_select on public.products for select to authenticated using ((select auth.uid()) = user_id);
create policy products_insert on public.products for insert to authenticated with check ((select auth.uid()) = user_id and current_stock = 0);
create policy products_update on public.products for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy sales_select on public.sales for select to authenticated using ((select auth.uid()) = user_id);
create policy sale_items_select on public.sale_items for select to authenticated using ((select auth.uid()) = user_id);
create policy inventory_select on public.inventory_movements for select to authenticated using ((select auth.uid()) = user_id);

grant usage on schema public to authenticated;
grant select, insert, update on public.profiles, public.products to authenticated;
grant select on public.sales, public.sale_items, public.inventory_movements to authenticated;
revoke all on public.sales, public.sale_items, public.inventory_movements from anon;

create function public.prevent_direct_stock_change() returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.current_stock is distinct from old.current_stock and coalesce(current_setting('ystio.stock_write', true),'off') <> 'on' then
    raise exception 'O estoque só pode ser alterado por movimentações.';
  end if;
  return new;
end; $$;
create trigger products_protect_stock before update on public.products for each row execute function public.prevent_direct_stock_change();

create function public.register_inventory_entry(p_product_id uuid,p_quantity integer,p_unit_cost numeric,p_notes text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_movement uuid; v_owner uuid;
begin
  if v_user is null then raise exception 'Não autenticado'; end if;
  if p_quantity <= 0 or p_unit_cost < 0 then raise exception 'Quantidade ou custo inválido'; end if;
  select user_id into v_owner from public.products where id=p_product_id for update;
  if v_owner is null or v_owner <> v_user then raise exception 'Produto não encontrado'; end if;
  perform set_config('ystio.stock_write','on',true);
  update public.products set current_stock=current_stock+p_quantity,unit_cost=p_unit_cost where id=p_product_id;
  insert into public.inventory_movements(user_id,product_id,movement_type,quantity,unit_cost,reference_type,notes)
  values(v_user,p_product_id,'entry',p_quantity,p_unit_cost,'inventory_entry',p_notes) returning id into v_movement;
  return v_movement;
end; $$;

create function public.register_sale(p_idempotency_key uuid,p_payment_method public.payment_method,p_received_amount numeric,p_items jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_sale uuid; v_total numeric(12,2):=0; v_item jsonb; v_product public.products%rowtype; v_qty integer;
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
    v_total := v_total + v_product.sale_price*v_qty;
  end loop;
  insert into public.sales(user_id,idempotency_key,calculated_total,received_amount,payment_method) values(v_user,p_idempotency_key,v_total,p_received_amount,p_payment_method) returning id into v_sale;
  perform set_config('ystio.stock_write','on',true);
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::integer;
    select * into v_product from public.products where id=(v_item->>'product_id')::uuid and user_id=v_user for update;
    insert into public.sale_items(user_id,sale_id,product_id,product_name,quantity,unit_price,unit_cost) values(v_user,v_sale,v_product.id,v_product.name,v_qty,v_product.sale_price,v_product.unit_cost);
    update public.products set current_stock=current_stock-v_qty where id=v_product.id;
    insert into public.inventory_movements(user_id,product_id,movement_type,quantity,unit_cost,reference_type,reference_id) values(v_user,v_product.id,'sale_out',-v_qty,v_product.unit_cost,'sale',v_sale);
  end loop;
  return v_sale;
end; $$;

create function public.cancel_sale(p_sale_id uuid) returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_sale public.sales%rowtype; v_item public.sale_items%rowtype;
begin
  if v_user is null then raise exception 'Não autenticado'; end if;
  select * into v_sale from public.sales where id=p_sale_id and user_id=v_user for update;
  if not found then raise exception 'Venda não encontrada'; end if;
  if v_sale.status='cancelled' then return; end if;
  perform set_config('ystio.stock_write','on',true);
  for v_item in select * from public.sale_items where sale_id=p_sale_id loop
    update public.products set current_stock=current_stock+v_item.quantity where id=v_item.product_id and user_id=v_user;
    insert into public.inventory_movements(user_id,product_id,movement_type,quantity,unit_cost,reference_type,reference_id,notes) values(v_user,v_item.product_id,'sale_cancellation',v_item.quantity,v_item.unit_cost,'sale',p_sale_id,'Restituição por cancelamento');
  end loop;
  update public.sales set status='cancelled',cancelled_at=now() where id=p_sale_id;
end; $$;

revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.register_inventory_entry(uuid,integer,numeric,text) from public, anon;
revoke all on function public.register_sale(uuid,public.payment_method,numeric,jsonb) from public, anon;
revoke all on function public.cancel_sale(uuid) from public, anon;
grant execute on function public.register_inventory_entry(uuid,integer,numeric,text) to authenticated;
grant execute on function public.register_sale(uuid,public.payment_method,numeric,jsonb) to authenticated;
grant execute on function public.cancel_sale(uuid) to authenticated;
