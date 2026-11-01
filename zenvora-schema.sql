-- =====================================================================
-- Zenvora / Realistic Mart : full backend schema (Supabase / Postgres)
-- Run ONCE: Supabase Dashboard > SQL Editor > New query > paste > Run
-- No demo users, no demo products. Real auth + real admin role.
-- =====================================================================

-- old jsonb tables from the previous version (kept as backup, not deleted)
alter table if exists public.orders        rename to orders_legacy;
alter table if exists public.site_settings rename to site_settings_legacy;

-- ---------- helper: is the current user an admin? ----------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text,
  name        text default '',
  phone       text default '',
  role        text not null default 'customer' check (role in ('customer','admin')),
  prime_until timestamptz,
  created_at  timestamptz default now()
);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

-- profile row is created automatically on sign-up
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'name', ''))
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- a customer can never make themselves admin / prime from the app
create or replace function public.protect_profile() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    new.role := old.role;
    new.prime_until := old.prime_until;
  end if;
  return new;
end $$;
drop trigger if exists protect_profile_trg on public.profiles;
create trigger protect_profile_trg before update on public.profiles
  for each row execute function public.protect_profile();

-- ---------- catalogue ----------
create table if not exists public.categories (
  id serial primary key, name text unique not null, icon text default '', sort int default 0
);
create table if not exists public.products (
  id          bigserial primary key,
  name        text not null,
  brand       text default '',
  category    text default '',
  price       numeric(10,2) not null check (price >= 0),
  mrp         numeric(10,2) not null check (mrp >= 0),
  description text default '',
  images      text[] default '{}',
  stock       int not null default 0 check (stock >= 0),
  gst_pct     int default 18,
  active      boolean default true,
  created_at  timestamptz default now()
);
create table if not exists public.banners (
  id bigserial primary key, image_url text not null, title text default '',
  link text default '', sort int default 0, active boolean default true
);
create table if not exists public.coupons (
  code text primary key, kind text not null check (kind in ('percent','flat')),
  value numeric not null, min_order numeric default 0,
  active boolean default true, expires_at timestamptz
);
create table if not exists public.app_settings (
  key text primary key, value jsonb not null, updated_at timestamptz default now()
);

-- ---------- customer data ----------
create table if not exists public.addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text, phone text, line1 text, city text, state text, pincode text,
  is_default boolean default false, created_at timestamptz default now()
);
create table if not exists public.wishlist (
  user_id uuid references auth.users(id) on delete cascade,
  product_id bigint references public.products(id) on delete cascade,
  primary key (user_id, product_id)
);
create table if not exists public.reviews (
  id bigserial primary key,
  product_id bigint references public.products(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  user_name text default '', rating int check (rating between 1 and 5),
  body text default '', created_at timestamptz default now()
);

-- ---------- orders ----------
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  status text not null default 'placed'
    check (status in ('placed','confirmed','packed','shipped','out_for_delivery','delivered','cancelled')),
  payment_method text not null check (payment_method in ('cod','online')),
  payment_status text not null default 'pending' check (payment_status in ('pending','paid','failed','refunded')),
  razorpay_order_id text, razorpay_payment_id text,
  subtotal numeric(10,2), discount numeric(10,2) default 0,
  delivery_fee numeric(10,2) default 0, total numeric(10,2),
  coupon text, address jsonb, otp text,
  created_at timestamptz default now()
);
create table if not exists public.order_items (
  id bigserial primary key,
  order_id uuid references public.orders(id) on delete cascade,
  product_id bigint references public.products(id),
  name text, price numeric(10,2), qty int check (qty > 0)
);
create index if not exists orders_user_idx on public.orders(user_id, created_at desc);

-- ---------- server-side logic (prices can't be faked from the app) ----------
create or replace function public.validate_coupon(p_code text, p_subtotal numeric)
returns numeric language plpgsql security definer set search_path = public as $$
declare c public.coupons%rowtype;
begin
  select * into c from coupons
   where upper(code) = upper(p_code) and active and (expires_at is null or expires_at > now());
  if not found then raise exception 'Invalid or expired coupon'; end if;
  if p_subtotal < c.min_order then raise exception 'Minimum order is %', c.min_order; end if;
  return least(p_subtotal, case when c.kind = 'percent' then round(p_subtotal * c.value / 100) else c.value end);
end $$;

create or replace function public.place_order(p_items jsonb, p_address jsonb, p_method text, p_coupon text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); it jsonb; pr public.products%rowtype; q int;
  sub numeric := 0; d_coupon numeric := 0; d_member numeric := 0; disc numeric;
  fee numeric; is_prime boolean; free_min numeric; ship numeric; oid uuid;
begin
  if uid is null then raise exception 'Please log in first'; end if;
  if p_method not in ('cod','online') then raise exception 'Bad payment method'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'Cart is empty'; end if;

  for it in select * from jsonb_array_elements(p_items) loop
    q := (it->>'qty')::int;
    if q is null or q < 1 then raise exception 'Bad quantity'; end if;
    select * into pr from products where id = (it->>'id')::bigint and active for update;
    if not found then raise exception 'A product is no longer available'; end if;
    if pr.stock < q then raise exception '% is out of stock', pr.name; end if;
    sub := sub + pr.price * q;
  end loop;

  select coalesce(prime_until > now(), false) into is_prime from profiles where id = uid;
  free_min := coalesce((select (value #>> '{}')::numeric from app_settings where key = 'free_delivery_min'), 999);
  ship     := coalesce((select (value #>> '{}')::numeric from app_settings where key = 'delivery_fee'), 49);
  fee := case when is_prime or sub >= free_min then 0 else ship end;

  d_member := case when is_prime
      then (case when sub > 1499 then sub * .15 when sub > 799  then sub * .10 else 0 end)
      else (case when sub > 2599 then sub * .15 when sub > 1299 then sub * .10 else 0 end) end;
  if p_coupon is not null and p_coupon <> '' then d_coupon := public.validate_coupon(p_coupon, sub); end if;
  disc := round(greatest(d_member, d_coupon));

  insert into orders (user_id, payment_method, subtotal, discount, delivery_fee, total, coupon, address, otp)
  values (uid, p_method, sub, disc, fee, sub - disc + fee, nullif(p_coupon,''), p_address,
          lpad(floor(random() * 10000)::int::text, 4, '0'))
  returning id into oid;

  for it in select * from jsonb_array_elements(p_items) loop
    select * into pr from products where id = (it->>'id')::bigint;
    insert into order_items (order_id, product_id, name, price, qty)
    values (oid, pr.id, pr.name, pr.price, (it->>'qty')::int);
    update products set stock = stock - (it->>'qty')::int where id = pr.id;
  end loop;
  return oid;
end $$;

create or replace function public.cancel_order(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update orders set status = 'cancelled'
   where id = p_id and user_id = auth.uid() and status in ('placed','confirmed');
  get diagnostics n = row_count;
  if n = 0 then raise exception 'This order can no longer be cancelled'; end if;
  update products p set stock = p.stock + oi.qty from order_items oi
   where oi.order_id = p_id and p.id = oi.product_id;
end $$;

-- ---------- Row Level Security ----------
alter table public.profiles    enable row level security;
alter table public.categories  enable row level security;
alter table public.products    enable row level security;
alter table public.banners     enable row level security;
alter table public.coupons     enable row level security;
alter table public.app_settings enable row level security;
alter table public.addresses   enable row level security;
alter table public.wishlist    enable row level security;
alter table public.reviews     enable row level security;
alter table public.orders      enable row level security;
alter table public.order_items enable row level security;

create policy "profile read"   on public.profiles for select to authenticated using (id = auth.uid() or public.is_admin());
create policy "profile update" on public.profiles for update to authenticated using (id = auth.uid() or public.is_admin());

create policy "cat read"   on public.categories for select using (true);
create policy "cat admin"  on public.categories for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "prod read"  on public.products for select using (active or public.is_admin());
create policy "prod admin" on public.products for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "ban read"   on public.banners for select using (active or public.is_admin());
create policy "ban admin"  on public.banners for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "set read"   on public.app_settings for select using (true);
create policy "set admin"  on public.app_settings for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "coupon admin" on public.coupons for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "addr own"  on public.addresses for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "wish own"  on public.wishlist  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "rev read"  on public.reviews for select using (true);
create policy "rev add"   on public.reviews for insert to authenticated with check (user_id = auth.uid());
create policy "rev del"   on public.reviews for delete to authenticated using (user_id = auth.uid() or public.is_admin());

-- orders: customers can only READ their own; creating/cancelling goes through the functions above
create policy "order read"   on public.orders for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy "order admin"  on public.orders for update to authenticated using (public.is_admin());
create policy "items read"   on public.order_items for select to authenticated
  using (public.is_admin() or exists (select 1 from public.orders o where o.id = order_id and o.user_id = auth.uid()));

-- ---------- product image storage ----------
insert into storage.buckets (id, name, public) values ('product-images', 'product-images', true)
on conflict (id) do nothing;
create policy "img public read" on storage.objects for select using (bucket_id = 'product-images');
create policy "img admin write" on storage.objects for all to authenticated
  using (bucket_id = 'product-images' and public.is_admin())
  with check (bucket_id = 'product-images' and public.is_admin());

-- live order updates in the admin panel / customer tracking
alter publication supabase_realtime add table public.orders;

-- ---------- starter settings (editable later from admin) ----------
insert into public.app_settings (key, value) values
  ('free_delivery_min', '999'), ('delivery_fee', '49'), ('store_name', '"Realistic Mart"')
on conflict (key) do nothing;

-- =====================================================================
-- AFTER RUNNING:
-- 1) Authentication > Providers > Email ON.  (Sign-ups ON for customers.)
-- 2) Create your own account in the app, then make yourself admin (run once):
--      update public.profiles set role = 'admin' where email = 'YOUR-EMAIL@gmail.com';
-- 3) Never put the service_role key or Razorpay secret in the app.
-- =====================================================================
