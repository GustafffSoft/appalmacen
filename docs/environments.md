# Development and production environments

## Branches

- `main`: production-ready releases only.
- `codex/develop`: integrated development and verification.
- `codex/feature-*`: isolated work before integration.

Promote changes through a reviewed merge from `codex/develop` to `main`.

## Firebase projects

| Environment | Project ID | Data policy |
| --- | --- | --- |
| Development | `appalmacen-5e987` | Test scans, random inventory and experiments are allowed. |
| Production | `appalmacen-prod-5e987` | Real operational data only. Never run random/seed scripts without an approved migration. |

Firebase aliases are stored in `mobile_app/.firebaserc` as `dev` and `prod`.

## Flutter builds

Development:

```powershell
.\scripts\build_web_dev.ps1 -BackendUrl http://10.0.0.28:8000
```

Production requires a separately deployed HTTPS backend configured with production Firebase credentials:

```powershell
.\scripts\build_web_prod.ps1 -BackendUrl https://your-production-backend.example.com
```

The production build uses `APP_ENV=prod`. It cannot silently fall back to the development backend.

## Backend environments

- Development reads `backend/.env`.
- Production reads `backend/.env.production` when `APP_ENV=production`.
- Hosted production should inject `FIREBASE_SERVICE_ACCOUNT_JSON` through its secret manager.
- Never commit `.env`, `.env.production`, service-account JSON, OpenAI keys, or generated logs.

Use `backend/.env.production.example` as the production variable checklist.

## Firebase rules

Development:

```powershell
.\scripts\deploy_firebase_rules.ps1 -Environment dev -IncludeStorage
```

Production:

```powershell
.\scripts\deploy_firebase_rules.ps1 -Environment prod -IncludeStorage
```

## One-time production console setup

The Firebase console requires two explicit confirmations on a new Spark project:

1. Authentication -> Get started -> enable Email/Password.
2. Storage -> Get started -> choose the US location and production rules.

After Authentication is enabled, register `gustafff93s@gmail.com`. The application and Firestore rules bootstrap that exact address as the initial administrator. All other accounts remain pending until an administrator assigns a role.

## Release checklist

1. Confirm `git status` is clean on `codex/develop`.
2. Run `flutter analyze` and `flutter test`.
3. Compile/import the FastAPI application.
4. Verify no secrets or generated logs are staged.
5. Merge reviewed changes into `main`.
6. Deploy the production backend with production secrets.
7. Build Flutter with `APP_ENV=prod` and the production backend URL.
8. Smoke-test authentication, product reads, image upload, and one reversible inventory workflow.

Do not copy the development Firestore database wholesale. Production should receive only approved catalog imports or explicit migration scripts.
