-- Sadhanapada security hardening and admin status transitions
-- Keep the public API surface narrow; all privileged implementation lives in private.

create or replace function private.request_device_token_hash()
returns text
language sql
stable
security invoker
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
security invoker
set search_path = ''
as $$
  select exists (
    select 1 from public.admins a
    where a.user_id = (select auth.uid())
  );
$$;

create or replace function private.validate_invite_code(p_code text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select p_code is not null and exists (
    select 1 from public.invite_codes i
    where i.code = trim(p_code)
      and i.used_by_device is null
      and (i.expires_at is null or i.expires_at > now())
  );
$$;

create or replace function private.device_invite_codes_enabled()
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

create or replace function private.request_device_access(
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

  perform pg_advisory_xact_lock(hashtextextended(p_token_hash, 0));
  select * into v_existing from public.devices d
  where d.token_hash = p_token_hash for update;

  if found then
    if v_existing.status = 'pending'
       and v_existing.last_seen_at < now() - interval '10 seconds' then
      update public.devices
      set name = trim(p_name),
          user_agent = left(coalesce(p_user_agent, ''), 1000),
          request_count = request_count + 1,
          last_seen_at = now()
      where id = v_existing.id
      returning * into v_existing;
    end if;
    return jsonb_build_object('id', v_existing.id, 'status', v_existing.status);
  end if;

  v_invites_enabled := private.device_invite_codes_enabled();
  if v_invites_enabled and not private.validate_invite_code(p_invite_code) then
    raise exception 'INVITE_CODE_INVALID';
  end if;

  insert into public.devices (
    id, name, token_hash, user_agent, invite_code_used, status, request_count, last_seen_at
  ) values (
    v_id, trim(p_name), p_token_hash, left(coalesce(p_user_agent, ''), 1000),
    case when v_invites_enabled then trim(p_invite_code) else null end,
    'pending', 1, now()
  )
  returning * into v_device;

  if v_invites_enabled then
    update public.invite_codes
    set used_by_device = v_id
    where code = trim(p_invite_code)
      and used_by_device is null
      and (expires_at is null or expires_at > now());
    if not found then raise exception 'INVITE_CODE_INVALID'; end if;
  end if;

  return jsonb_build_object('id', v_device.id, 'status', v_device.status);
end;
$$;

create or replace function private.get_device_access_status(p_token_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_device public.devices%rowtype;
  v_header_hash text := (select private.request_device_token_hash());
begin
  if p_token_hash is null
     or p_token_hash !~ '^[0-9a-f]{64}$'
     or v_header_hash is null
     or p_token_hash <> v_header_hash then
    return null;
  end if;

  update public.devices d
  set last_seen_at = now()
  where d.token_hash = v_header_hash
  returning d.* into v_device;

  if not found then return null; end if;
  return jsonb_build_object(
    'id', v_device.id,
    'name', v_device.name,
    'status', v_device.status,
    'created_at', v_device.created_at,
    'last_seen_at', v_device.last_seen_at,
    'request_count', v_device.request_count,
    'approved_at', v_device.approved_at
  );
end;
$$;

-- Public PostgREST entry points run as invoker and delegate to narrow private routines.
create or replace function public.device_invite_codes_enabled()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select private.device_invite_codes_enabled(); $$;

create or replace function public.request_device_access(
  p_name text, p_token_hash text, p_user_agent text, p_invite_code text default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select private.request_device_access(p_name,p_token_hash,p_user_agent,p_invite_code); $$;

create or replace function public.get_device_access_status(p_token_hash text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select private.get_device_access_status(p_token_hash); $$;

drop function if exists public.validate_invite_code(text);
drop function if exists public.touch_device_seen();

revoke all on all functions in schema public from public, anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;

grant execute on function public.device_invite_codes_enabled() to anon;
grant execute on function public.request_device_access(text,text,text,text) to anon;
grant execute on function public.get_device_access_status(text) to anon;

grant execute on function private.request_device_token_hash() to anon, authenticated;
grant execute on function private.is_admin() to authenticated;
grant execute on function private.is_approved_device() to anon, authenticated;
grant execute on function private.device_invite_codes_enabled() to anon;
grant execute on function private.request_device_access(text,text,text,text) to anon;
grant execute on function private.get_device_access_status(text) to anon;

drop policy if exists "device reads own row or admin reads all" on public.devices;
drop policy if exists "admins read all devices" on public.devices;
create policy "admins read all devices"
  on public.devices for select to authenticated
  using ((select private.is_admin()));

revoke all privileges on table public.devices from anon, authenticated;
revoke select (id,name,token_hash,user_agent,invite_code_used,status,created_at,last_seen_at,request_count,approved_at)
  on table public.devices from anon, authenticated;
revoke update (status) on table public.devices from authenticated;
grant select (id,name,user_agent,invite_code_used,status,created_at,last_seen_at,request_count,approved_at)
  on table public.devices to authenticated;
grant update (status) on table public.devices to authenticated;

revoke all privileges on table public.admins from anon, authenticated;
grant select on table public.admins to authenticated;

revoke all privileges on table public.invite_codes from anon, authenticated;
grant select, insert, update, delete on table public.invite_codes to authenticated;
revoke all privileges on table public.device_access_settings from anon, authenticated;
grant select, update on table public.device_access_settings to authenticated;

drop index if exists public.devices_last_seen_at_idx;
