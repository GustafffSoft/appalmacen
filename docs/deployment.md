# Production deployment

The production browser application uses one public origin:

```text
https://appalmacen-prod-5e987.web.app
```

Firebase Hosting serves Flutter Web and rewrites `/api/**` to the
`appalmacen-api` Cloud Run service in `us-east1`. Cloud Run validates a Firebase
ID token and the active user profile before executing protected routes.

## Prerequisites

1. Upgrade `appalmacen-prod-5e987` to the Blaze billing plan.
2. Install and authenticate Google Cloud CLI (`gcloud auth login`). The local
   installer is `Google.CloudSDK` when using Windows Package Manager.
3. Authenticate Firebase CLI (`firebase login`).
4. In Firebase Console, enable Email/Password Authentication, Firestore,
   Storage and Hosting for the production project.

## One-time Google Cloud setup

From the repository root:

```powershell
.\scripts\setup_google_cloud_prod.ps1
```

The script enables the required APIs, creates the dedicated Cloud Run service
account, grants only Firestore and Firebase Auth read access, creates the
OpenAI secret and optionally adds its first value.

Do not place service-account JSON or the OpenAI key in `.env.production`, the
Docker image or the Git repository.

## Deploy the backend

```powershell
.\scripts\deploy_backend_prod.ps1
```

The service is publicly reachable because Firebase Hosting must invoke it, but
application routes remain protected by Firebase ID-token validation. Only
`/`, `/api/v1/health` and Cloud Run infrastructure endpoints are public.

## Deploy Firebase rules

```powershell
.\scripts\deploy_firebase_rules.ps1 -Environment prod -IncludeStorage
```

## Deploy Flutter Web

```powershell
.\scripts\deploy_web_prod.ps1
```

The production build cannot fall back to a local IP address. It sends API
requests to the Hosting origin, which forwards `/api/**` to Cloud Run.

## Smoke test

1. Open `https://appalmacen-prod-5e987.web.app` in a private browser window.
2. Confirm an unauthenticated user only sees the login screen.
3. Register `gustafff93s@gmail.com` and verify its admin profile.
4. Confirm a newly registered non-admin account remains pending.
5. Create one test product without adding stock.
6. Create one pallet with a photo and verify inventory increases once.
7. Move the pallet between a rack position and the unlocated area.
8. Scan one product image and one invoice image.
9. Confirm the Cloud Run logs contain no authorization or server errors.

## Rollback

Firebase Hosting releases can be rolled back from the Hosting console. Cloud
Run keeps immutable revisions; route traffic back to the previous healthy
revision from the Cloud Run revisions screen.
