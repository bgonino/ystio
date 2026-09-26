create or replace function public.link_product_batch(p_product_id uuid, p_batch_id uuid default null, p_supplier_id uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare
  v_user uuid:=auth.uid(); v_batch uuid:=p_batch_id; v_number integer;
  v_product public.products%rowtype; v_item record;
begin
  if v_user is null then raise exception 'Não autenticado'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user::text,0));
  select * into v_product from public.products where id=p_product_id and user_id=v_user for update;
  if not found then raise exception 'Produto não encontrado'; end if;
  if p_supplier_id is not null and not exists(select 1 from public.suppliers where id=p_supplier_id and user_id=v_user) then raise exception 'Fornecedor não encontrado'; end if;
  if v_batch is null then
    select coalesce(max(batch_number),0)+1 into v_number from public.inventory_batches where user_id=v_user;
    insert into public.inventory_batches(user_id,batch_number,supplier_id,notes)
      values(v_user,v_number,p_supplier_id,'Lote criado para organizar estoque existente') returning id into v_batch;
  elsif not exists(select 1 from public.inventory_batches where id=v_batch and user_id=v_user) then
    raise exception 'Lote não encontrado';
  end if;
  for v_item in select * from public.inventory_batch_items where user_id=v_user and product_id=p_product_id and batch_id<>v_batch for update loop
    insert into public.inventory_batch_assignments(user_id,product_id,batch_id,previous_quantity,assigned_quantity,notes)
      values(v_user,p_product_id,v_item.batch_id,v_item.quantity,0,'Reclassificação para outro lote; saldo e vendas preservados');
    delete from public.inventory_batch_items where id=v_item.id;
  end loop;
  perform public.assign_existing_stock_to_batch(p_product_id,v_batch,v_product.current_stock,'Vínculo do estoque existente na edição do produto');
  update public.products set active_batch_id=v_batch where id=p_product_id and user_id=v_user;
  return v_batch;
end; $$;
revoke all on function public.link_product_batch(uuid,uuid,uuid) from public,anon;
grant execute on function public.link_product_batch(uuid,uuid,uuid) to authenticated;
