# auth-web

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
