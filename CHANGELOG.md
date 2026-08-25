
## 0.12.1 - 2026-08-25

### Fixed
- Forward user bearer token instead of shared secret



## 0.12.0 - 2026-08-25

### Added
- Extract user-facing strings into locale resources
- Provision a users-api identity during login callback



## 0.11.0 - 2026-08-23

### Added
- Wire session expiry policy from environment


### Fixed
- Fix cpu resource limit quantity that never matched ArgoCD's applied manifest



## 0.10.0 - 2026-08-19

### Added
- Add ASSETS_URL and SHARED_URL to dev and local configmaps
- Add structured logging and OTel tracing


### Documentation
- Update title and add badges


### Fixed
- Wrap long lines and fix indentation in Auth0Config
- Remove duplicate logging bootstrap, guard tracing bootstrap
- Actually propagate trace context to auth-api
- Sort imports lexicographically in TracingSetup



## 0.9.0 - 2026-08-14

### Added
- Route generic error status codes to shared-web


### Fixed
- Encode the shared session's expiry as RFC 3339, not a Double



## 0.8.4 - 2026-08-14

### Fixed
- Percent-encode Auth0 query values so + survives round-trip



## 0.8.3 - 2026-08-13

### Fixed
- Key pending logins by state to avoid a login-race expiry



## 0.8.2 - 2026-08-13

### Fixed
- Key pending logins by state to avoid a login-race expiry



## 0.8.1 - 2026-08-12

### Fixed
- Handle Auth0 token exchange failures gracefully



## 0.8.0 - 2026-08-12

### Added
- Report build version on /status/ping



## 0.7.0 - 2026-08-12

### Added
- Preserve return path through logout


### Documentation
- Document logout-complete Allowed Logout URLs prerequisite



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
