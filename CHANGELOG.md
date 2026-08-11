
## 0.6.0 - 2026-08-11

### Added
- Add expiry to the shared session, sourced from Auth0's token lifetime



## 0.5.0 - 2026-08-11

### Added
- Carry the Auth0 access token in the shared session



## 0.4.0 - 2026-08-07

### Added
- Forward inbound traceparent header to auth-api


### Fixed
- Correct AUTH_API_URL port to match auth-api's Service



## 0.3.0 - 2026-08-07

### Added
- Use sweetrpg/redis-session-driver instead of local driver
- Repoint authz check at auth-api



## 0.2.0 - 2026-08-04

### Added
- Gate /auth/login behind admin-api maintenance mode
- Add guarded Sentry error reporting


### Documentation
- Document the Auth0 application setup


### Fixed
- Point auth-web at the shared sweetrpg-support Redis
- Mount redis-auth secret so REDIS_PASS reaches the app
- Give login failures a specific, safe reason code instead of a flag


## 0.1.0 - 2026-08-02

### Fixed
- Point auth-web at the shared sweetrpg-support Redis


## 0.1.0 - 2026-08-01

### Added
- Implement Auth0 login flow and shared session


## Unreleased

### Added
- Initial scaffold: Vapor server, Auth0 Authorization Code login flow (`/auth/login`,
  `/auth/callback`, `/auth/logout`), shared session establishment (Redis-backed, `sub`/name/
  email/roles verified via `users-api`'s `/authz/check`), Docker image build, and Kubernetes
  manifests (including this app's own dedicated Redis instance).
