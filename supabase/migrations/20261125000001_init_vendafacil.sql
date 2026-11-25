-- Migração inicial do ERP VendaFácil (PostgreSQL + RLS + Transações)

create extension if not exists "pgcrypto";

-- 1. Perfis de usuários (espelha auth.users para vínculo de operadores por e-mail)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Perfis visíveis para usuários autenticados"
  on public.profiles for select
  to authenticated
  using (true);

create policy "Usuário insere próprio perfil"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, lower(new.email))
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 2. Lojas
create table if not exists public.stores (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

-- 3. Membros da loja (admin e operator)
create table if not exists public.store_members (
  store_id uuid not null references public.stores(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('admin', 'operator')),
  created_at timestamptz not null default now(),
  primary key (store_id, user_id)
);

-- Trigger para adicionar o criador da loja como admin automaticamente
create or replace function public.handle_new_store()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.store_members (store_id, user_id, role)
  values (new.id, new.owner_id, 'admin')
  on conflict (store_id, user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_store_created on public.stores;
create trigger on_store_created
  after insert on public.stores
  for each row execute procedure public.handle_new_store();

alter table public.stores enable row level security;
alter table public.store_members enable row level security;

create policy "Membros visualizam suas lojas"
  on public.stores for select
  to authenticated
  using (
    owner_id = auth.uid()
    or exists (
      select 1 from public.store_members sm
      where sm.store_id = stores.id and sm.user_id = auth.uid()
    )
  );

create policy "Usuário autenticado cria loja"
  on public.stores for insert
  to authenticated
  with check (owner_id = auth.uid());

create policy "Membros visualizam membros da mesma loja"
  on public.store_members for select
  to authenticated
  using (
    exists (
      select 1 from public.store_members sm
      where sm.store_id = store_members.store_id and sm.user_id = auth.uid()
    )
  );

create policy "Admin adiciona operadores na loja"
  on public.store_members for insert
  to authenticated
  with check (
    exists (
      select 1 from public.store_members sm
      where sm.store_id = store_members.store_id
        and sm.user_id = auth.uid()
        and sm.role = 'admin'
    )
  );

-- 4. Produtos
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  code text not null,
  name text not null,
  price numeric(12,2) not null check (price >= 0),
  stock integer not null default 0 check (stock >= 0),
  min_stock integer not null default 0 check (min_stock >= 0),
  created_at timestamptz not null default now(),
  unique (store_id, code)
);

alter table public.products enable row level security;

create policy "Membros consultam produtos da loja"
  on public.products for select
  to authenticated
  using (
    exists (
      select 1 from public.store_members sm
      where sm.store_id = products.store_id and sm.user_id = auth.uid()
    )
  );

create policy "Admin gerencia produtos da loja"
  on public.products for all
  to authenticated
  using (
    exists (
      select 1 from public.store_members sm
      where sm.store_id = products.store_id
        and sm.user_id = auth.uid()
        and sm.role = 'admin'
    )
  )
  with check (
    exists (
      select 1 from public.store_members sm
      where sm.store_id = products.store_id
        and sm.user_id = auth.uid()
        and sm.role = 'admin'
    )
  );

-- 5. Vendas e Itens da Venda
create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  operator_id uuid not null references auth.users(id),
  payment_method text not null check (payment_method in ('Dinheiro', 'Pix', 'Cartão de Crédito', 'Cartão de Débito')),
  total numeric(12,2) not null default 0,
  status text not null default 'completed' check (status in ('completed', 'canceled')),
  created_at timestamptz not null default now()
);

create table if not exists public.sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete cascade,
  product_id uuid not null references public.products(id),
  product_code text not null,
  product_name text not null,
  quantity integer not null check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0)
);

alter table public.sales enable row level security;
alter table public.sale_items enable row level security;

create policy "Membros visualizam vendas da loja"
  on public.sales for select
  to authenticated
  using (
    exists (
      select 1 from public.store_members sm
      where sm.store_id = sales.store_id and sm.user_id = auth.uid()
    )
  );

create policy "Membros visualizam itens das vendas da loja"
  on public.sale_items for select
  to authenticated
  using (
    exists (
      select 1 from public.sales s
      join public.store_members sm on sm.store_id = s.store_id
      where s.id = sale_items.sale_id and sm.user_id = auth.uid()
    )
  );

-- 6. RPC Transacional: Confirmar Venda (valida preço, estoque e dá baixa atomicamente)
create or replace function public.confirm_sale(
  p_store_id uuid,
  p_payment_method text,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale_id uuid;
  v_total numeric(12,2) := 0;
  v_item jsonb;
  v_prod record;
  v_qty integer;
begin
  if not exists (
    select 1 from public.store_members
    where store_id = p_store_id and user_id = auth.uid()
  ) then
    raise exception 'Sem permissão nesta loja.';
  end if;

  if jsonb_array_length(p_items) = 0 then
    raise exception 'Carrinho vazio.';
  end if;

  insert into public.sales (store_id, operator_id, payment_method, total, status)
  values (p_store_id, auth.uid(), p_payment_method, 0, 'completed')
  returning id into v_sale_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_qty := (v_item->>'quantity')::integer;
    if v_qty <= 0 then
      raise exception 'Quantidade inválida.';
    end if;

    select * into v_prod
    from public.products
    where id = (v_item->>'product_id')::uuid
      and store_id = p_store_id
    for update;

    if not found then
      raise exception 'Produto não encontrado.';
    end if;

    if v_prod.stock < v_qty then
      raise exception 'Estoque insuficiente para % (disponível: %).', v_prod.name, v_prod.stock;
    end if;

    update public.products
    set stock = stock - v_qty
    where id = v_prod.id;

    insert into public.sale_items (sale_id, product_id, product_code, product_name, quantity, unit_price)
    values (v_sale_id, v_prod.id, v_prod.code, v_prod.name, v_qty, v_prod.price);

    v_total := v_total + (v_prod.price * v_qty);
  end loop;

  update public.sales set total = v_total where id = v_sale_id;
  return v_sale_id;
end;
$$;

-- 7. RPC Transacional: Cancelar Venda (somente admin) e devolver itens ao estoque
create or replace function public.cancel_sale(p_sale_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale record;
  v_item record;
begin
  select * into v_sale from public.sales where id = p_sale_id for update;
  if not found then
    raise exception 'Venda não encontrada.';
  end if;

  if not exists (
    select 1 from public.store_members
    where store_id = v_sale.store_id
      and user_id = auth.uid()
      and role = 'admin'
  ) then
    raise exception 'Apenas administradores podem cancelar vendas.';
  end if;

  if v_sale.status = 'canceled' then
    return;
  end if;

  for v_item in select * from public.sale_items where sale_id = p_sale_id
  loop
    update public.products
    set stock = stock + v_item.quantity
    where id = v_item.product_id;
  end loop;

  update public.sales set status = 'canceled' where id = p_sale_id;
end;
$$;

-- 8. RPC para adicionar operador por e-mail
create or replace function public.add_store_operator(p_store_id uuid, p_email text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target_user_id uuid;
begin
  if not exists (
    select 1 from public.store_members
    where store_id = p_store_id
      and user_id = auth.uid()
      and role = 'admin'
  ) then
    raise exception 'Apenas administradores podem adicionar operadores.';
  end if;

  select id into v_target_user_id
  from public.profiles
  where lower(email) = lower(trim(p_email));

  if not found then
    raise exception 'Usuário não encontrado. Peça ao operador para cadastrar e confirmar a conta primeiro.';
  end if;

  insert into public.store_members (store_id, user_id, role)
  values (p_store_id, v_target_user_id, 'operator')
  on conflict (store_id, user_id) do nothing;
end;
$$;
