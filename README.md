# SweetRPG Auth Web

[![CI](https://github.com/sweetrpg/auth-web/actions/workflows/ci.yaml/badge.svg)](https://github.com/sweetrpg/auth-web/actions/workflows/ci.yaml)
[![License](https://img.shields.io/github/license/sweetrpg/auth-web.svg)](https://img.shields.io/github/license/sweetrpg/auth-web.svg)
[![Issues](https://img.shields.io/github/issues/sweetrpg/auth-web.svg)](https://img.shields.io/github/issues/sweetrpg/auth-web.svg)
[![PRs](https://img.shields.io/github/issues-pr/sweetrpg/auth-web.svg)](https://img.shields.io/github/issues-pr/sweetrpg/auth-web.svg)
[![Dependabot](https://badgen.net/github/dependabot/sweetrpg/auth-web)](https://badgen.net/github/dependabot/sweetrpg/auth-web)
[![Deployment](https://argocd.dev.pilgrimagesoftware.com/api/badge?name=sweetrpg-auth-web&revision=true&showAppName=true&namespace=sweetrpg-system)](https://argocd.dev.pilgrimagesoftware.com/applications/sweetrpg-auth-web)

Suite-wide login for the SweetRPG platform. Sole implementer of the Auth0 Authorization Code
flow (`/auth/login`, `/auth/callback`, `/auth/logout`) and the only frontend holding Auth0 client
credentials. Establishes one shared session (cookie + Redis-backed store) that every other
frontend (`main-web`, `catalog-web`, `admin-web`, `users-web`) reads directly - logging in once
is recognized suite-wide.

See `AGENTS.md` for contributor/agent guidance, and `sweetrpg/platform`'s
`openspec/changes/add-user-api-authn-authz` for the design this repo implements.

## Running Checks Locally

```bash
swift build
swift test
```

`swift run` serves on `:8080`. Without `AUTH0_DOMAIN`/`AUTH0_CLIENT_ID` set, `/auth/login`
returns a 503 rather than starting a broken flow. Without `REDIS_HOST` set, falls back to
in-memory sessions - fine for local development, not for anything another frontend needs to read
from.
