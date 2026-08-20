# NANDAL MVP

This is a static NANDAL website served locally by Python. Its production services are provided by Supabase:

- Supabase Auth with email verification
- Managed PostgreSQL, storage, realtime messaging, RLS policies, reports and moderation schema

## Run locally

The easiest local preview command (uses the Python bundled with Codex where available) is:

```powershell
.\start-nandal.ps1
```

Then open `http://localhost:8000`. Before user registration will work, run `supabase-schema.sql` in your Supabase SQL Editor and enable email confirmation in Authentication settings.

If you already deployed an earlier schema, re-run the whole file again — every statement is written to be safe to re-run (`create or replace`, `if not exists`, `drop policy if exists`), including the photo policies and the moderation/account-deletion additions near the bottom.

### Moderation

There's no self-serve way to become a moderator — that's intentional, since a member could otherwise set the flag on their own account. Grant it by hand in the Supabase SQL Editor:

```sql
update public.profiles set is_moderator = true where id = '<user-uuid>';
```

Once set, that member sees a "Moderation" tab in the app with the open reports queue.

If PowerShell blocks the local script, run this one-time command in the same folder, then start it again:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

## Before public launch

Use HTTPS via Nginx/Caddy, a strong secret stored in the server environment, managed PostgreSQL, email verification, rate limits, CSRF protections/cookie sessions, image scanning, audit logging, backup/restore tests, consent/privacy tools, and active moderation.

Account deletion is currently self-service data scrubbing (see `delete_own_account` in the schema) — it clears the profile and photos and blocks further sign-in, but it can't delete the underlying Supabase Auth credential from client-side code, since that requires the service-role key. Wire that up as a trusted server-side job (e.g. a Supabase Edge Function calling `auth.admin.deleteUser`) before launch if full credential removal is a requirement.

A stray `nandal.db` SQLite file from an earlier pre-Supabase prototype was removed from this project — it held a leftover local user record and had nothing to do with the current Supabase-backed app. `.gitignore` now excludes `*.db` and `.env` so similar artifacts don't get committed by accident.
