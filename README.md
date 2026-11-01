# Realistic Mart (Zenvora) – Flutter app

1. Supabase: run `zenvora-schema.sql`, then `zenvora-schema-v2-features.sql`.
2. Create your account in the app, then in Supabase SQL Editor run:
   `update public.profiles set role = 'admin' where email = 'YOUR-EMAIL';`
3. Put this folder on GitHub (main branch). Actions tab > "Build Android APK" > Run workflow.
4. Download the APK from the run's Artifacts.
Keys / admin access code: `lib/config.dart`.
