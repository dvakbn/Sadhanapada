# Sadhanapada device approval setup

This branch adds an approval gate in front of the existing local-first Sadhanapada PWA and a separate Supabase-authenticated admin page at `/admin/`.

## Important current-app detail

Sadhanapada is a vanilla HTML/CSS/JavaScript PWA. Its tracker, reflections, and journal are currently stored in browser `localStorage`; the repository did not contain Supabase-backed application-data tables. This change gates app initialization and provides an RLS helper for any future Supabase data tables. It does not migrate existing local data into Supabase.

## 1. Create the Supabase project

1. Create a Supabase project.
2. In Project Settings → API, copy the Project URL and the public anon/publishable key.
3. Never use the service-role/secret key in this website.

## 2. Run the SQL migration

Open Supabase → SQL Editor → New query. Copy and run the complete file:

`supabase/migrations/001_device_approval.sql`

The migration creates the `devices`, `invite_codes`, `admins`, and `device_access_settings` tables, enables RLS, creates restricted functions, and adds the approval timestamp trigger.

## 3. Create your admin account

1. In Supabase → Authentication → Users, choose Add user.
2. Enter your admin email and a strong password. Confirm the user if the dashboard offers that option.
3. Copy the new user's UUID.
4. In SQL Editor, run this statement after replacing the email:

```sql
insert into public.admins (user_id, email)
select id, email
from auth.users
where lower(email) = lower('you@example.com')
on conflict (user_id) do update set email = excluded.email;
```

The admin page first authenticates with Supabase Auth, then verifies that the signed-in user's UUID exists in `public.admins`. A normal authenticated user cannot add themselves to this table through the frontend.

## 4. Optional invite codes

Invite codes are disabled by default. To require one for each new device request, run:

```sql
update public.device_access_settings
set invite_codes_enabled = true
where id = 1;

insert into public.invite_codes (code, expires_at)
values
  ('REPLACE-WITH-A-LONG-RANDOM-CODE', now() + interval '30 days');
```

Create one row per invite code. Each code is atomically assigned to the first device that successfully submits it. To disable invite codes later:

```sql
update public.device_access_settings
set invite_codes_enabled = false
where id = 1;
```

## 5. Deploy on Netlify or Vercel

This build generates an ignored `supabase-config.js` from environment variables. The public anon/publishable key is expected to be visible in browser code; RLS is the security boundary. No service-role key is used.

### Netlify

1. Import this GitHub repository and select branch `feature/device-approval`.
2. In Site configuration → Environment variables, add:
   - `SUPABASE_URL` = your Supabase Project URL
   - `SUPABASE_ANON_KEY` = your public anon/publishable key
3. Build command: `npm run build`
4. Publish directory: `.`
5. Deploy. Your admin URL will be `https://YOUR-SITE.netlify.app/admin/`.

The included `netlify.toml` already contains the build command and publish directory.

### Vercel

1. Import the repository and select branch `feature/device-approval`.
2. In Project → Settings → Environment Variables, add:
   - `SUPABASE_URL` = your Supabase Project URL
   - `SUPABASE_ANON_KEY` = your public anon/publishable key
3. Build command: `npm run build`
4. Output directory: `.`
5. Redeploy. Your admin URL will be `https://YOUR-SITE.vercel.app/admin/`.

The included `vercel.json` sets these build values.

### GitHub Pages note

GitHub Pages does not run this Node build step or inject environment variables. Use Netlify or Vercel for this setup, or add a carefully configured GitHub Actions deployment workflow that supplies the public variables during build. Do not commit `supabase-config.js`.

## 6. Local build

Copy `.env.example` to `.env`, fill in your URL and public key, then export those variables in your shell before running `npm run build`. The small build script reads environment variables directly and does not load `.env` itself.

## 7. Test checklist

- [ ] Open the site in a new browser profile. It shows **Request access**, and a row appears in Admin → Pending.
- [ ] Approve it. The waiting screen detects approval within about 10 seconds and opens the app.
- [ ] Open a second browser profile and request access. Reject it; the app remains hidden there.
- [ ] Revoke the first device from Admin → Approved. The open app locks on its next approval heartbeat (up to 30 seconds); a reload is denied.
- [ ] Open `/admin/` signed out. No device rows are queried or displayed; the login form is shown.
- [ ] Sign in with a normal Supabase user not listed in `admins`. The session is rejected and device data stays hidden.
- [ ] If invite codes are enabled, test one valid code, one invalid code, and reuse of the same code.

## Security design and remaining limitations

- The browser generates a 16-byte random token (32 hex characters); SHA-256 of that token is stored in `devices.token_hash`. The raw token stays in that browser's localStorage and is not sent to the database.
- The hash is attached to the standard Supabase `x-client-info` request header as `sadhanapada-device/<hash>`. This avoids requiring an additional custom browser header. The SQL reads that header through PostgREST's request context.
- A unique constraint on `token_hash` means one device has at most one device row and one pending request. Repeated submissions update the same pending row and increment `request_count`.
- Device users can only select the row matching their request-header hash. The admin page uses the anon key plus a Supabase Auth session; RLS limits admin queries and status changes to users present in `admins`.
- The service-role/secret key is not required and must never be added to the frontend or Git.
- This is **browser-profile approval**, not hardware attestation. Clearing site data, using another browser/profile, or reinstalling the browser creates a new token and requires approval again. A determined user who controls the browser can inspect localStorage and network requests; this is not DRM or a tamper-proof identity system.
- The raw local app database remains in localStorage and is not encrypted. The gate prevents the app UI from initializing before approval, but it cannot hide localStorage from the owner of that browser profile or protect data copied before revocation.
- Revocation is checked every 30 seconds while the app is open and on every reload. During a network outage, an already-open approved session stays usable until the network returns; a fresh page load fails closed if Supabase cannot verify approval. Offline reloads therefore cannot be guaranteed while also enforcing fresh revocation checks.
- Existing Sadhanapada data is device-local. If you later add cloud data tables, enable RLS on every table and apply the migration's example `private.is_approved_device()` policy to the required operations. There are currently no Supabase app-data tables in this repository to alter.
- The browser's user-agent string is only a hint and can be spoofed. It is not used as an authentication factor.
