# AGENTS.md

This file provides guidance to Claude Code, Codex, GitHub Copilot, and other coding agents
working in this repository.

## About This Project

`auth-web` is suite-wide login for the SweetRPG platform - the sole implementer of the Auth0
Authorization Code flow (`/auth/login`, `/auth/callback`, `/auth/logout`) and the only frontend
holding Auth0 client credentials. It establishes one shared session (cookie + Redis-backed
store) that every other frontend reads directly, so logging in once through this app is
recognized suite-wide rather than each frontend running its own independent login. See
`sweetrpg/platform`'s `openspec/changes/add-user-api-authn-authz` for the full design and why
this exists as its own repo (deliberately kept small - login is infrastructure every other
frontend hard-depends on, so it gets the smallest possible blast radius) rather than being
bundled into `main-web`, `users-web`, or `admin-web`.

### Dependencies within the platform

- **users-api**: called once at login, `POST /authz/check`, to establish the session's verified
  roles server-side - not a local unverified token decode.
- **Redis**: the shared `redis.sweetrpg-support.svc.cluster.local` instance, DB index 2 - not a
  dedicated instance for this app (an earlier draft provisioned one, since removed). This app is
  the sole writer for that index; see `sweetrpg/platform`'s `docs/frontend-conventions.md`
  ("Shared sweetrpg-support Redis instance") for the full DB-index registry across every
  consumer of that instance before picking a different index.
- **Every other frontend** reads the session this app writes (same cookie name, same Redis
  instance) but never writes to it - they only ever redirect an unauthenticated visitor to this
  app's `/auth/login?return_to=<path>`.

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
