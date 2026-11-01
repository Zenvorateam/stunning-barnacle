-- =====================================================================
-- Zenvora schema v2 : extra features (run AFTER zenvora-schema.sql)
-- Supabase Dashboard > SQL Editor > New query > paste > Run
-- Adds: staff role, return/cancel/refund requests with photos, verified
-- reviews with photos + moderation, smarter coupons, store design
-- (banners, categories, theme, legal pages), cart sync, NOTIFICATIONS.
-- NO ads system (removed as requested).
-- =====================================================================

-- ---------- roles: customer / staff / admin ----------
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('customer','staff','admin'));
alter table public.profiles add column if not exists blocked boolean default false;

create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role in ('admin','staff'));
$$;

-- staff can work on orders; only admin can touch everything else
drop policy if exists "order read" on public.orders;
drop policy if exists "order admin" on public.orders;
create policy "order read"  on public.orders for select to authenticated using (user_id = auth.uid() or public.is_staff());
create policy "order staff" on public.orders for update to authenticated using (public.is_staff());
drop policy if exists "items read" on public.order_items;
create policy "items read" on public.order_items for select to authenticated
  using (public.is_staff() or exists (select 1 from public.orders o where o.id = order_id and o.user_id = auth.uid()));

-- ---------- store design (all editable from admin) ----------
alter table public.banners add column if not exists mobile_image_url text default '';
alter table public.banners add column if not exists heading text default '';
alter table public.banners add column if not exists body text default '';
alter table public.banners add column if not exists button_text text default '';
alter table public.banners add column if not exists bg_color text default '#17251f';
alter table public.banners add column if not exists text_color text default '#ffffff';
alter table public.banners add column if not exists starts_at timestamptz;
alter table public.banners add column if not exists ends_at timestamptz;

alter table public.categories add column if not exists emoji text default '';
alter table public.categories add column if not exists bg_color text default '#dcebb8';
alter table public.categories add column if not exists text_color text default '#17251f';
alter table public.categories add column if not exists active boolean default true;

insert into public.app_settings (key, value) values
  ('theme', '{"preset":"forest","primary":"#17251f","accent":"#d7f76b","bg":"#faf9f5","productGradient":"mint","categoryGradient":"lavender"}'),
  ('brand', '{"name":"Realistic Mart","logo_url":"","contact_email":"","whatsapp":""}'),
  ('delivery', '{"origin_pin":"","cutoff_hour":14,"holidays":[]}'),
  ('footer_links', '{"help":"","shipping":"","returns":"","faq":"","contact":""}'),
  ('privacy_text', '""'), ('terms_text', '""'),
  ('prime_plans', '[{"months":1,"price":29},{"months":2,"price":49}]'),
  ('banner_autoslide', '{"enabled":true,"seconds":4}')
on conflict (key) do nothing;

-- ---------- smarter coupons ----------
alter table public.coupons add column if not exists assigned_email text;
alter table public.coupons add column if not exists usage_limit int;
alter table public.coupons add column if not exists used_count int default 0;
alter table public.coupons add column if not exists per_user_limit int default 1;
create table if not exists public.coupon_uses (
  id bigserial primary key, code text, user_id uuid, order_id uuid, used_at timestamptz default now()
);
alter table public.coupon_uses enable row level security;
create policy "coupon uses admin" on public.coupon_uses for select to authenticated using (public.is_admin());

create or replace function public.validate_coupon(p_code text, p_subtotal numeric)
returns numeric language plpgsql security definer set search_path = public as $$
declare c public.coupons%rowtype; my_email text; used int;
begin
  select * into c from coupons where upper(code) = upper(p_code);
  if not found then raise exception 'This coupon code does not exist'; end if;
  if not c.active then raise exception 'This coupon is switched off'; end if;
  if c.expires_at is not null and c.expires_at <= now() then raise exception 'This coupon has expired'; end if;
  if c.usage_limit is not null and coalesce(c.used_count,0) >= c.usage_limit then raise exception 'This coupon has reached its usage limit'; end if;
  if c.assigned_email is not null and c.assigned_email <> '' then
    select email into my_email from profiles where id = auth.uid();
    if lower(coalesce(my_email,'')) <> lower(c.assigned_email) then raise exception 'This coupon is not for your account'; end if;
  end if;
  select count(*) into used from coupon_uses where upper(code) = upper(c.code) and user_id = auth.uid();
  if used >= coalesce(c.per_user_limit, 1) then raise exception 'You have already used this coupon'; end if;
  if p_subtotal < c.min_order then raise exception 'Add items worth Rs % or more to use this coupon', c.min_order; end if;
  return least(p_subtotal, case when c.kind = 'percent' then round(p_subtotal * c.value / 100) else c.value end);
end $$;

-- count a coupon as used the moment an order that carries it is created
create or replace function public.track_coupon_use() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.coupon is not null then
    insert into coupon_uses (code, user_id, order_id) values (new.coupon, new.user_id, new.id);
    update coupons set used_count = coalesce(used_count,0) + 1 where upper(code) = upper(new.coupon);
  end if;
  return new;
end $$;
drop trigger if exists track_coupon_use_trg on public.orders;
create trigger track_coupon_use_trg after insert on public.orders
  for each row execute function public.track_coupon_use();

-- ---------- cancel / return / refund requests (with photo proof) ----------
create table if not exists public.service_requests (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('cancel','return','refund')),
  reason text not null, message text default '',
  photos text[] default '{}' check (coalesce(array_length(photos,1),0) <= 3),
  status text not null default 'pending' check (status in ('pending','approved','rejected','withdrawn','completed')),
  admin_note text default '',
  created_at timestamptz default now(), updated_at timestamptz default now()
);
create unique index if not exists one_pending_request on public.service_requests(order_id, kind) where status = 'pending';
alter table public.service_requests enable row level security;
create policy "sr read"   on public.service_requests for select to authenticated using (user_id = auth.uid() or public.is_staff());
create policy "sr insert" on public.service_requests for insert to authenticated
  with check (user_id = auth.uid() and status = 'pending'
              and exists (select 1 from public.orders o where o.id = order_id and o.user_id = auth.uid()));
create policy "sr edit own" on public.service_requests for update to authenticated
  using (user_id = auth.uid() and status = 'pending') with check (user_id = auth.uid() and status in ('pending','withdrawn'));
create policy "sr staff"  on public.service_requests for update to authenticated using (public.is_staff());

-- ---------- verified reviews: only after delivery, photos, admin approval ----------
alter table public.reviews add column if not exists photos text[] default '{}';
alter table public.reviews add column if not exists status text default 'pending';
alter table public.reviews drop constraint if exists reviews_status_check;
alter table public.reviews add constraint reviews_status_check check (status in ('pending','approved','hidden'));
drop policy if exists "rev read" on public.reviews;
drop policy if exists "rev add" on public.reviews;
drop policy if exists "rev del" on public.reviews;
create policy "rev read"  on public.reviews for select using (status = 'approved' or user_id = auth.uid() or public.is_staff());
create policy "rev mod"   on public.reviews for update to authenticated using (public.is_staff());
create policy "rev del"   on public.reviews for delete to authenticated using (user_id = auth.uid() or public.is_admin());

create or replace function public.submit_review(p_product bigint, p_rating int, p_body text, p_photos text[] default '{}')
returns bigint language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); rid bigint; nm text;
begin
  if uid is null then raise exception 'Please log in first'; end if;
  if not exists (select 1 from orders o join order_items i on i.order_id = o.id
                 where o.user_id = uid and o.status = 'delivered' and i.product_id = p_product) then
    raise exception 'You can review a product only after it is delivered to you';
  end if;
  if coalesce(array_length(p_photos,1),0) > 3 then raise exception 'Maximum 3 photos'; end if;
  select name into nm from profiles where id = uid;
  insert into reviews (product_id, user_id, user_name, rating, body, photos, status)
  values (p_product, uid, coalesce(nm,''), p_rating, coalesce(p_body,''), coalesce(p_photos,'{}'), 'pending')
  returning id into rid;
  return rid;
end $$;

-- ---------- cart that follows the user across devices ----------
create table if not exists public.cart_items (
  user_id uuid references auth.users(id) on delete cascade,
  product_id bigint references public.products(id) on delete cascade,
  qty int not null check (qty > 0), primary key (user_id, product_id)
);
alter table public.cart_items enable row level security;
create policy "cart own" on public.cart_items for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- NOTIFICATIONS (admin sends, users get inbox + push) ----------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  title text not null, body text default '', image_url text default '',
  target text not null default 'all' check (target in ('all','prime','user')),
  user_id uuid references auth.users(id) on delete cascade,   -- only when target = 'user'
  link text default '',                                        -- e.g. product:12 or order:<id>
  created_by uuid references auth.users(id), created_at timestamptz default now()
);
create table if not exists public.notification_reads (
  user_id uuid references auth.users(id) on delete cascade,
  notification_id uuid references public.notifications(id) on delete cascade,
  primary key (user_id, notification_id)
);
create table if not exists public.device_tokens (
  token text primary key, user_id uuid references auth.users(id) on delete cascade,
  platform text default 'android', updated_at timestamptz default now()
);
alter table public.notifications enable row level security;
alter table public.notification_reads enable row level security;
alter table public.device_tokens enable row level security;

create policy "notif read" on public.notifications for select to authenticated using (
  target = 'all'
  or (target = 'user'  and user_id = auth.uid())
  or (target = 'prime' and exists (select 1 from public.profiles p where p.id = auth.uid() and p.prime_until > now()))
  or public.is_admin());
create policy "notif admin" on public.notifications for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "reads own"   on public.notification_reads for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "token own"   on public.device_tokens for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "token admin" on public.device_tokens for select to authenticated using (public.is_admin());

-- automatic message to the customer whenever an order's status changes
create or replace function public.notify_order_status() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    insert into notifications (title, body, target, user_id, link)
    values ('Order update', 'Your order is now: ' || replace(new.status, '_', ' '), 'user', new.user_id, 'order:' || new.id);
  end if;
  return new;
end $$;
drop trigger if exists notify_order_status_trg on public.orders;
create trigger notify_order_status_trg after update on public.orders
  for each row execute function public.notify_order_status();

alter publication supabase_realtime add table public.notifications;

-- ---------- private storage for return / cancel proof, public for review photos ----------
insert into storage.buckets (id, name, public) values ('order-evidence', 'order-evidence', false) on conflict (id) do nothing;
insert into storage.buckets (id, name, public) values ('review-photos',  'review-photos',  true)  on conflict (id) do nothing;
insert into storage.buckets (id, name, public) values ('store-media',    'store-media',    true)  on conflict (id) do nothing;

-- files go in a folder named after the user's id:  <user-id>/<file>
create policy "evidence own write" on storage.objects for insert to authenticated
  with check (bucket_id = 'order-evidence' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "evidence read" on storage.objects for select to authenticated
  using (bucket_id = 'order-evidence' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_staff()));
create policy "review photo read"  on storage.objects for select using (bucket_id = 'review-photos');
create policy "review photo write" on storage.objects for insert to authenticated
  with check (bucket_id = 'review-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "store media read"  on storage.objects for select using (bucket_id = 'store-media');
create policy "store media admin" on storage.objects for all to authenticated
  using (bucket_id = 'store-media' and public.is_admin()) with check (bucket_id = 'store-media' and public.is_admin());

-- =====================================================================
-- Team: make someone staff (orders + requests + review moderation only):
--   update public.profiles set role = 'staff' where email = 'staff@gmail.com';
-- (Admin screen will do this with a button, no SQL needed later.)
-- =====================================================================
