# AGENTS.md

This file provides guidance to Claude Code, Codex, GitHub Copilot, and other coding agents
working in this repository.

## About This Project

`auth-web` is suite-wide login for the SweetRPG platform - the sole implementer of the Auth0
Authorization Code flow (`/auth/login`, `/auth/callback`, `/auth/logout`) and the only frontend
holding Auth0 client credentials. It establishes one shared session (cookie + Redis-backed
store) that every other frontend reads directly, so logging in once through this app is
recognized suite-wide rather than each frontend running its own independent login. See
`sweetrpg/platform`'s `openspec/changes/add-user-api-authn-authz` for the original design and why
this exists as its own repo (deliberately kept small - login is infrastructure every other
frontend hard-depends on, so it gets the smallest possible blast radius) rather than being
bundled into `main-web`, `users-web`, or `admin-web`. Its authz backend moved from `users-api` to
a dedicated `auth-api` - see `openspec/changes/split-authz-into-auth-api` for why.

### Dependencies within the platform

- **auth-api**: called once at login, `POST /authz/check`, to establish the session's verified
  roles server-side - not a local unverified token decode.
- **Redis**: this app's own dedicated instance, `redis.sweetrpg-auth.svc.cluster.local`, deployed
  alongside it in `sweetrpg-auth`. It doubles as the suite-wide session store - see
  `sweetrpg/platform`'s `docs/frontend-conventions.md` ("Per-namespace Redis instances") for how
  other frontends read it cross-namespace.
- **Every other frontend** reads the session this app writes (same cookie name, same Redis
  instance) but never writes to it - they only ever redirect an unauthenticated visitor to this
  app's `/auth/login?return_to=<path>`.

### Auth0 application setup

One Auth0 application backs both `dev` and `local` environments today (same tenant, same
client id/secret - see `kubernetes/overlays/{dev,local}/secrets.yaml`'s shared Akeyless path
`/sweetrpg/dev/auth/auth0`). None of this is scripted or captured in Terraform/Akeyless as
code - it's manual dashboard configuration, so if the application is ever deleted, the tenant
is rebuilt, or a genuinely separate environment (e.g. production) needs its own application,
here's what has to exist for login to work:

- **Application type**: Regular Web Application (confidential client - `auth-web` holds
  `AUTH0_CLIENT_SECRET` and exchanges the authorization code server-side; never a SPA/public
  client).
- **Grant type**: Authorization Code only.
- **Allowed Callback URLs**: one entry per environment sharing this application - both
  `https://dev.sweetrpg.com/auth/callback` and `https://sweetrpg.local/auth/callback` need to
  be present simultaneously for `dev` and `local` to both work, since they share one
  application. A production environment would add its own callback URL here, or - more likely,
  see below - get its own separate application instead.
- **Allowed Logout URLs**: the same set of origins, but the *post-logout redirect target*
  (`returnTo`), not the callback path - `https://dev.sweetrpg.com/auth/logout-complete` and
  `https://sweetrpg.local/auth/logout-complete` (see `Auth0Config.logoutURL(returnTo:)`, which
  derives this from `AUTH0_CALLBACK_URL` by swapping `/auth/callback` for
  `/auth/logout-complete`). Auth0 only accepts a `returnTo` that exactly matches one of these
  registered URLs, so the visitor's actual post-logout destination can't be registered directly -
  it travels as `/auth/logout-complete`'s own `return_to` query parameter instead, which this app
  validates and redirects to itself (see `openspec/changes/auth-web-logout-preserve-return-path`
  in `sweetrpg/platform`). This is a separate list from Allowed Callback URLs in the Auth0
  dashboard - missing an entry here doesn't break login, only logout, and manifests as Auth0's
  own generic "Oops, something went wrong" error page after clicking "Log out," not an error this
  app's own logs will show anything useful for (confirmed the hard way: the redirect to Auth0
  succeeds, Auth0 is the one rejecting the `returnTo` value).
- **Connections enabled**: at minimum the connection(s) actually used to sign in - confirmed in
  use: a social connection (GitHub) and email/password (`Username-Password-Authentication`).
  Enable whichever connections the product actually wants to offer; nothing in this app
  hardcodes which ones are available, that's entirely an Auth0-dashboard setting.
- **An API registered for `AUTH0_AUDIENCE`** (Applications → APIs → Create API, *not* the
  application settings page): `auth-api` and `auth-web` both validate/request tokens against
  this API's Identifier. Without a real API registered, `AUTH0_AUDIENCE` has nothing valid to
  point at, and `auth-api`'s `verifyIntendedAudience` check fails for every token regardless of
  how correctly everything else is configured - confirmed the hard way: an *empty* string
  synced into `AUTH0_AUDIENCE` (a stale/never-populated Akeyless value, not a missing
  environment variable - `Environment.get` treats an empty string as present) passed
  `auth-api`'s `Auth0Config.fromEnvironment()` `guard let` without error, then failed every
  login at token-verification time with no indication why. Confirming the deployed value is
  actually non-empty (`kubectl exec ... -- env | grep AUTH0_AUDIENCE`) is a faster diagnostic
  than assuming the dashboard side is wrong.
- **Akeyless**: `AUTH0_DOMAIN`, `AUTH0_CLIENT_ID`, `AUTH0_CLIENT_SECRET`, `AUTH0_AUDIENCE` at
  `/sweetrpg/dev/auth/auth0`, read by both this app's and `auth-api`'s `ExternalSecret`s (see
  `auth-api`'s `AGENTS.md`, "the one shared Auth0 application"). A new environment needing its
  own application (production, most likely, rather than sharing the `dev` tenant) should follow
  the same `/sweetrpg/<env>/auth/auth0` path convention rather than inventing a new one.

None of the actual credential values belong in this file or any committed doc - Akeyless is the
source of truth; this section documents the *shape* of what must exist there and in the Auth0
dashboard, not the values themselves.

### Routing

Unlike `catalog-web`/`admin-web` (whose Ingress strips their own `/catalog`/`/admin` prefix
before the request reaches the app), this app's Ingress does **not** strip `/auth` - its routes
are already registered as `/auth/login`, `/auth/callback`, `/auth/logout`, matching the
browser-facing path one-to-one. See `kubernetes/overlays/dev/ingress.yaml`.

## Committing Code

[Conventional Commits](https://www.conventionalcommits.org/): `<type>(<scope>): <description>`.

## Branches and Workflow

Git-flow (see `docs/git-flow.md` in `sweetrpg/platform`): `develop` is the integration branch,
`master` reflects the latest release. Feature/fix branches off `develop`, PR back into `develop`.

## Running Checks Locally

```bash
swift build
swift test
```

`swift run` serves on `:8080`. Without `AUTH0_DOMAIN`/`AUTH0_CLIENT_ID` set, `/auth/login`
returns a 503 rather than starting a broken flow. Without `REDIS_HOST` set, falls back to
in-memory sessions - fine for local development, not for anything another frontend needs to read
from.
