-- Sadhanapada device approval
-- Run this entire migration in Supabase SQL Editor before deploying the gated frontend.

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated;

create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists public.devices (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 100),
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  user_agent text not null default '',
  invite_code_used text,
  status text not null default 'pending' check (status in ('pending','approved','rejected','revoked')),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  request_count integer not null default 1 check (request_count >= 1),
  approved_at timestamptz
);

create table if not exists public.invite_codes (
  code text primary key check (char_length(trim(code)) between 6 and 100),
  used_by_device uuid unique references public.devices(id) on delete set null,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.device_access_settings (
  id integer primary key check (id = 1),
  invite_codes_enabled boolean not null default false
);
insert into public.device_access_settings (id, invite_codes_enabled)
values (1, false)
on conflict (id) do nothing;

create index if not exists devices_status_created_at_idx
  on public.devices(status, created_at desc);
create index if not exists devices_last_seen_at_idx
  on public.devices(last_seen_at desc);

alter table public.admins enable row level security;
alter table public.devices enable row level security;
alter table public.invite_codes enable row level security;
alter table public.device_access_settings enable row level security;

-- Read the device hash from a standard Supabase CORS-approved request header.
-- The browser sends: x-client-info: sadhanapada-device/<64-char-sha256-hex>
create or replace function private.request_device_token_hash()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select substring(
    coalesce(current_setting('request.headers', true)::jsonb ->> 'x-client-info', '')
    from '^sadhanapada-device/([0-9a-f]{64})$'
  );
$$;

create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.admins a
    where a.user_id = (select auth.uid())
  );
$$;

create or replace function private.is_approved_device()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.devices d
    where d.token_hash = (select private.request_device_token_hash())
      and d.status = 'approved'
  );
$$;

grant execute on function private.request_device_token_hash() to anon, authenticated;
grant execute on function private.is_admin() to anon, authenticated;
grant execute on function private.is_approved_device() to anon, authenticated;

-- Admins can read only their own allow-list row. No client can add itself as an admin.
drop policy if exists "admins read own row" on public.admins;
create policy "admins read own row"
  on public.admins for select to authenticated
  using (user_id = (select auth.uid()));
revoke all on public.admins from anon, authenticated;
grant select on public.admins to authenticated;

-- Devices: a device can read only its own row; admins can read all rows.
drop policy if exists "device reads own row or admin reads all" on public.devices;
create policy "device reads own row or admin reads all"
  on public.devices for select to anon, authenticated
  using (
    token_hash = (select private.request_device_token_hash())
    or (select private.is_admin())
  );

-- Status changes are available only to an authenticated admin. Column-level
-- UPDATE prevents changing device names, hashes, or request metadata in the UI.
drop policy if exists "admins update device status" on public.devices;
create policy "admins update device status"
  on public.devices for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

revoke all on public.devices from anon, authenticated;
grant select on public.devices to anon, authenticated;
grant update (status) on public.devices to authenticated;

-- Invite codes are never directly readable by anon clients. They are checked
-- only inside the SECURITY DEFINER functions below.
drop policy if exists "admins manage invite codes" on public.invite_codes;
create policy "admins manage invite codes"
  on public.invite_codes for all to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));
revoke all on public.invite_codes from anon, authenticated;
grant select, insert, update, delete on public.invite_codes to authenticated;

drop policy if exists "admins manage device access settings" on public.device_access_settings;
create policy "admins manage device access settings"
  on public.device_access_settings for all to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));
revoke all on public.device_access_settings from anon, authenticated;
grant select, update on public.device_access_settings to authenticated;

create or replace function public.device_invite_codes_enabled()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select s.invite_codes_enabled from public.device_access_settings s where s.id = 1),
    false
  );
$$;

create or replace function public.validate_invite_code(p_code text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_code is not null and exists (
    select 1
    from public.invite_codes i
    where i.code = trim(p_code)
      and i.used_by_device is null
      and (i.expires_at is null or i.expires_at > now())
  );
$$;

create or replace function public.request_device_access(
  p_name text,
  p_token_hash text,
  p_user_agent text,
  p_invite_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing public.devices%rowtype;
  v_device public.devices%rowtype;
  v_id uuid := gen_random_uuid();
  v_invites_enabled boolean;
begin
  if p_name is null or char_length(trim(p_name)) not between 1 and 100 then
    raise exception 'NAME_REQUIRED';
  end if;

  if p_token_hash is null
     or p_token_hash !~ '^[0-9a-f]{64}$'
     or p_token_hash <> (select private.request_device_token_hash()) then
    raise exception 'DEVICE_TOKEN_HEADER_MISMATCH';
  end if;

  -- Serialize concurrent submissions for the same device token.
  perform pg_advisory_xact_lock(hashtextextended(p_token_hash, 0));

  select * into v_existing
  from public.devices d
  where d.token_hash = p_token_hash
  for update;

  if found then
    if v_existing.status = 'pending' then
      update public.devices
      set name = trim(p_name),
          user_agent = left(coalesce(p_user_agent, ''), 1000),
          request_count = request_count + 1,
          last_seen_at = now()
      where id = v_existing.id
      returning * into v_existing;
    else
      update public.devices
      set last_seen_at = now()
      where id = v_existing.id
      returning * into v_existing;
    end if;

    return jsonb_build_object('id', v_existing.id, 'status', v_existing.status);
  end if;

  v_invites_enabled := public.device_invite_codes_enabled();

  if v_invites_enabled and not public.validate_invite_code(p_invite_code) then
    raise exception 'INVITE_CODE_INVALID';
  end if;

  insert into public.devices (
    id, name, token_hash, user_agent, invite_code_used, status, request_count, last_seen_at
  ) values (
    v_id,
    trim(p_name),
    p_token_hash,
    left(coalesce(p_user_agent, ''), 1000),
    case when v_invites_enabled then trim(p_invite_code) else null end,
    'pending',
    1,
    now()
  )
  returning * into v_device;

  if v_invites_enabled then
    update public.invite_codes
    set used_by_device = v_id
    where code = trim(p_invite_code)
      and used_by_device is null
      and (expires_at is null or expires_at > now());

    if not found then
      raise exception 'INVITE_CODE_INVALID';
    end if;
  end if;

  return jsonb_build_object('id', v_device.id, 'status', v_device.status);
end;
$$;

create or replace function public.touch_device_seen()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
  v_hash text := (select private.request_device_token_hash());
begin
  if v_hash is null then
    return null;
  end if;

  update public.devices
  set last_seen_at = now()
  where token_hash = v_hash
  returning status into v_status;

  return v_status;
end;
$$;

-- Do not leave SECURITY DEFINER RPCs executable by PUBLIC by default.
revoke execute on function public.device_invite_codes_enabled() from public;
revoke execute on function public.validate_invite_code(text) from public;
revoke execute on function public.request_device_access(text, text, text, text) from public;
revoke execute on function public.touch_device_seen() from public;
grant execute on function public.device_invite_codes_enabled() to anon, authenticated;
-- Invite validation is intentionally not exposed as a public oracle; it is called
-- internally by request_device_access(), which is SECURITY DEFINER.
grant execute on function public.request_device_access(text, text, text, text) to anon;
grant execute on function public.touch_device_seen() to anon, authenticated;

-- Automatically stamp the first approval time. The admin UI only updates status.
create or replace function private.set_device_approved_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    new.approved_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists devices_set_approved_at on public.devices;
create trigger devices_set_approved_at
before update of status on public.devices
for each row execute function private.set_device_approved_at();

-- Example protection for any future Supabase-backed app data table:
-- alter table public.your_app_data enable row level security;
-- create policy "approved devices may use app data"
--   on public.your_app_data for all to anon, authenticated
--   using ((select private.is_approved_device()))
--   with check ((select private.is_approved_device()));
--
-- The current Sadhanapada tracker stores its journal and entries in browser
-- localStorage, not Supabase tables. The frontend gate runs before init()/load(),
-- but localStorage is not encrypted against the owner of that browser profile.
