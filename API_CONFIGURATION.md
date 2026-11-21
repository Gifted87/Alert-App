# App wide API configuration

API providers are configured for the whole app build. Users cannot enter their
own provider URLs or keys, and API credentials are not included in account
backups or synced through Firestore.

1. Copy `api.env.json.example` to `api.env.json` in the project root.
2. Set `LLM_BASE_URL`, `LLM_API_KEY`, `LLM_MODEL`, `REALMARKET_BASE_URL`, and
   `REALMARKET_API_KEY` in that file.
3. Run or build with `--dart-define-from-file=api.env.json`:

   ```powershell
   flutter run --dart-define-from-file=api.env.json
   flutter build apk --release --dart-define-from-file=api.env.json
   ```

`api.env.json` is ignored by Git. Builds made without it use the default
OpenRouter endpoint and `nvidia/nemotron-3.5-super-vl:free` model, and have an
empty provider key. A build-time define is compiled
into the mobile app and can be extracted from its APK. For production provider
secrets, route calls through an authenticated backend and keep the keys in
server-side environment secrets instead. Every app install must receive a new
build to use changed values.
