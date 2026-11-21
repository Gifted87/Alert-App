# TenX Admin Console

An iOS inspired operations panel for shared TenX Markets settings. Firebase Authentication signs in the operator; Firestore stores app-wide settings and change history. It uses Firestore and Firebase Hosting without Cloud Functions.

## Grant admin access

1. Sign in to the panel with the Firebase account that should be an administrator. The account must have a verified email.
2. If that account has no admin role, the panel displays its Firebase UID and the exact Firestore record to create.
3. In Firebase Console, open Firestore and create `adminUsers/{uid}` where `{uid}` is the displayed UID. Add exactly these fields:
   - `role` (string): `admin`
   - `uid` (string): the displayed UID
   - `email` (string): the email address shown by the panel
4. Return to the panel and select **Check admin access**.

The panel cannot grant admin access to itself. Firestore Rules allow an account to read only its own role record and deny all client writes to `adminUsers`.

## Firestore structure

- `adminUsers/{uid}`: trusted, manually provisioned admin role.
- `appConfig/current`: live shared settings and publication metadata.
- `appConfig/current/versions/{versionId}`: settings history used by the restore UI.
- `strategyCatalog/{entryId}`: shared strategy or specialist JSON, with draft/published/archived state.
- `strategyCatalogHistory/{eventId}`: append-only audit snapshots for catalog edits and deletes.
- `users/{uid}/aiStrategies` and `users/{uid}/aiSpecialists`: each user's saved definitions; the console can import the signed-in admin's items as drafts.

Authenticated app users can read current settings. Only a verified account with a valid admin role can publish settings or access history. The app uses local defaults and its Firestore cache while offline.

## Run and deploy

```powershell
cd admin-panel
npm install
npm run dev
```

From the repository root, deploy rules before using the panel, then build and deploy Hosting:

```powershell
npx firebase-tools@latest deploy --only firestore:rules --project tenx-markets
npm --prefix admin-panel run build
npx firebase-tools@latest deploy --only hosting --project tenx-markets
```

Panel: <https://tenx-markets-admin.web.app>. Enable the desired Firebase Authentication providers and authorize the Hosting domain in Firebase Authentication settings.

## Strategy catalog, analytics, and diagnostics

Open **Strategies & specialists** to create definitions, paste/edit JSON, publish, archive, or delete entries. **Import my saved items** copies definitions belonging to the signed-in admin into draft entries. The app listens only to published catalog entries, replaces matching built-in defaults, overlays shared specialist definitions in strategies, and stores a local-only catalog snapshot for offline use. Archiving/deleting a published definition removes it on the next online catalog sync; devices retain their last snapshot while offline.

The **Analytics & diagnostics** page links to Firebase Analytics and Crashlytics. The app reports screen views and privacy-limited alert/AI analysis events; it avoids symbols, prices, prompt content, email addresses, and provider response bodies. Flutter fatal and uncaught async errors are sent to Crashlytics. The console does not call the LLM provider and never contains its API key; run the connection check from the app.

## Scope

The panel controls the shared LLM model, output limit, timeout, optional splash promotion, in-app message bar, and published strategy/specialist catalog. The message bar's subject, tagline, HTTPS link, optional image URL, and enabled state are saved to Firestore. Signed-in clients check the active content 30 seconds after app launch; dismissing it hides it for the rest of that app launch. It does not edit the Remote Config template.
