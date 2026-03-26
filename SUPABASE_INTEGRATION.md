# BiznisPlus SaaS Multi-Tenant (Flutter + Supabase)

This document defines the target SaaS architecture for BiznisPlus so multiple companies can use the same app safely, with strict data isolation by `company_id`.

## 1. SaaS Objective

- Single application instance for many companies (tenants)
- Every business record includes `company_id`
- Users can only access data belonging to their company
- Keep all existing product features while moving from local storage to cloud

## 2. Multi-Tenant Design

Tenant key is `company_id`.

Rules:

- Every row in `products`, `categories`, `stock_movements` includes `company_id`
- User profile row stores `company_id`
- RLS policies use `company_id = current_user_company_id`
- Flutter queries always filter by `company_id`

## 3. Required Database Structure (Supabase/PostgreSQL)

The following SQL includes your required tables and production-safe constraints.

```sql
create extension if not exists "pgcrypto";

-- 1) companies
create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  email text not null,
  subscription_status text not null default 'trial',
  created_at timestamptz not null default now()
);

-- 2) users (profile table linked to auth.users)
-- Note: this is NOT auth.users; this is your business profile table.
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  company_id uuid not null references public.companies(id) on delete restrict,
  created_at timestamptz not null default now()
);

-- 3) categories
create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  company_id uuid not null references public.companies(id) on delete cascade,
  created_at timestamptz not null default now()
);

-- 4) products
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  price numeric(12,2) not null default 0,
  quantity integer not null default 0,
  min_stock integer not null default 5,
  category_id uuid null references public.categories(id) on delete set null,
  company_id uuid not null references public.companies(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 5) stock_movements
create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  type text not null check (type in ('entry', 'exit', 'adjustment')),
  quantity integer not null check (quantity >= 0),
  created_at timestamptz not null default now(),
  company_id uuid not null references public.companies(id) on delete cascade
);

create index if not exists idx_users_company_id on public.users(company_id);
create index if not exists idx_categories_company_id on public.categories(company_id);
create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_products_category_id on public.products(category_id);
create index if not exists idx_stock_movements_company_id on public.stock_movements(company_id);
create index if not exists idx_stock_movements_product_id on public.stock_movements(product_id);

create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_products_updated_at on public.products;
create trigger trg_products_updated_at
before update on public.products
for each row execute function public.set_updated_at();
```

## 4. RLS Policies for Tenant Isolation

```sql
alter table public.companies enable row level security;
alter table public.users enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.stock_movements enable row level security;

-- Helper function: company of connected user
create or replace function public.current_company_id()
returns uuid
language sql
stable
as $$
  select company_id from public.users where id = auth.uid();
$$;

-- companies
create policy "companies_select_own" on public.companies
for select using (id = public.current_company_id());

create policy "companies_update_own" on public.companies
for update using (id = public.current_company_id());

-- users
create policy "users_select_own_company" on public.users
for select using (company_id = public.current_company_id());

create policy "users_insert_self" on public.users
for insert with check (id = auth.uid());

create policy "users_update_self" on public.users
for update using (id = auth.uid());

-- categories
create policy "categories_select_company" on public.categories
for select using (company_id = public.current_company_id());

create policy "categories_insert_company" on public.categories
for insert with check (company_id = public.current_company_id());

create policy "categories_update_company" on public.categories
for update using (company_id = public.current_company_id());

create policy "categories_delete_company" on public.categories
for delete using (company_id = public.current_company_id());

-- products
create policy "products_select_company" on public.products
for select using (company_id = public.current_company_id());

create policy "products_insert_company" on public.products
for insert with check (company_id = public.current_company_id());

create policy "products_update_company" on public.products
for update using (company_id = public.current_company_id());

create policy "products_delete_company" on public.products
for delete using (company_id = public.current_company_id());

-- stock_movements
create policy "movements_select_company" on public.stock_movements
for select using (company_id = public.current_company_id());

create policy "movements_insert_company" on public.stock_movements
for insert with check (company_id = public.current_company_id());

create policy "movements_update_company" on public.stock_movements
for update using (company_id = public.current_company_id());

create policy "movements_delete_company" on public.stock_movements
for delete using (company_id = public.current_company_id());
```

## 5. Authentication and Onboarding Flow

When a user registers:

1. Create auth user via Supabase Auth
2. Create `companies` row
3. Create `users` profile row with `company_id`
4. App reads `company_id` from `users` table and stores it in memory/session

Recommended implementation:

- Use an Edge Function (or secure SQL RPC) for atomic onboarding
- Keep Flutter client on `anon` key only

### Option A: Secure RPC for onboarding

```sql
create or replace function public.create_company_for_current_user(
  company_name text,
  company_email text
)
returns uuid
language plpgsql
security definer
as $$
declare
  new_company_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  insert into public.companies(name, email, subscription_status)
  values (company_name, company_email, 'trial')
  returning id into new_company_id;

  insert into public.users(id, email, company_id)
  values (auth.uid(), company_email, new_company_id)
  on conflict (id) do update set company_id = excluded.company_id;

  return new_company_id;
end;
$$;
```

## 6. Flutter Architecture (Keep Existing Structure)

Keep:

- `lib/core/`
- `lib/data/models/`
- `lib/data/providers/`
- `lib/presentation/`

Add service layer:

- `lib/services/supabase_client_service.dart`
- `lib/services/auth_service.dart`
- `lib/services/company_service.dart`
- `lib/services/inventory_supabase_service.dart`

Provider responsibilities:

- `InventoryProvider` remains UI state orchestrator
- data reads/writes delegated to `InventorySupabaseService`
- local `shared_preferences` removed from core CRUD path

## 7. Example Flutter Code

### 7.1 Auth service (register/login/logout)

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _sb = Supabase.instance.client;

  Future<void> register({
    required String email,
    required String password,
    required String companyName,
  }) async {
    final auth = await _sb.auth.signUp(email: email, password: password);
    if (auth.user == null) {
      throw Exception('Inscription echouee');
    }

    await _sb.rpc('create_company_for_current_user', params: {
      'company_name': companyName,
      'company_email': email,
    });
  }

  Future<void> login({required String email, required String password}) async {
    await _sb.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> logout() async {
    await _sb.auth.signOut();
  }
}
```

### 7.2 Fetching products filtered by `company_id`

```dart
Future<List<Map<String, dynamic>>> fetchProducts(String currentCompanyId) async {
  final supabase = Supabase.instance.client;

  final rows = await supabase
      .from('products')
      .select()
      .eq('company_id', currentCompanyId)
      .order('name');

  return List<Map<String, dynamic>>.from(rows);
}
```

### 7.3 Adding stock movement with tenant filter

```dart
Future<void> addStockMovement({
  required String companyId,
  required String productId,
  required String type,
  required int quantity,
}) async {
  final supabase = Supabase.instance.client;

  final product = await supabase
      .from('products')
      .select('id, quantity, company_id')
      .eq('id', productId)
      .eq('company_id', companyId)
      .single();

  final currentQty = product['quantity'] as int;
  int nextQty = currentQty;

  if (type == 'entry') nextQty += quantity;
  if (type == 'exit') nextQty = (currentQty - quantity).clamp(0, 1 << 31);
  if (type == 'adjustment') nextQty = quantity;

  await supabase.from('products').update({
    'quantity': nextQty,
  }).eq('id', productId).eq('company_id', companyId);

  await supabase.from('stock_movements').insert({
    'product_id': productId,
    'type': type,
    'quantity': quantity,
    'company_id': companyId,
  });
}
```

### 7.4 Subscription status check

```dart
Future<String> getSubscriptionStatus(String companyId) async {
  final supabase = Supabase.instance.client;

  final row = await supabase
      .from('companies')
      .select('subscription_status')
      .eq('id', companyId)
      .single();

  return row['subscription_status'] as String;
}
```

## 8. InventoryProvider Migration Blueprint

Replace local storage operations with Supabase calls:

- `initialize()`:
  - resolve current user
  - fetch profile from `users`
  - read `company_id`
  - load `categories`, `products`, `stock_movements`
- `addOrUpdateProduct()`:
  - `upsert` into `products` with `company_id`
- `deleteProduct()`:
  - delete by `id` + `company_id`
- `addOrUpdateCategory()` / `deleteCategory()`:
  - same pattern by `company_id`
- `addStockMovement()`:
  - enforce product in same `company_id`
  - update stock + insert movement

## 9. Existing Features to Keep (SaaS version)

All current features stay:

- Dashboard KPIs
- Product CRUD
- Category CRUD
- Stock movements (entry, exit, adjustment)
- Reports
- Settings page

Only the persistence layer changes from local to Supabase.

## 10. Best Practices for Flutter + Supabase SaaS

- Never use `service_role` key in the app client
- Keep all tenant security in RLS (not only in Flutter filters)
- Include `company_id` in every business table and query
- Add audit fields where needed (`created_by`, `updated_by`)
- Use transactions/RPC for stock-sensitive logic
- Add unit tests for quantity changes and tenant isolation
- Add monitoring for auth failures and RLS denials

## 11. Deployment Checklist

- Supabase project created
- SQL schema executed
- RLS enabled and policies created
- onboarding RPC or Edge Function ready
- Flutter keys set in `AppConstants`
- Provider migrated to service layer
- End-to-end tested with two companies (isolation proof)
