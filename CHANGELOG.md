
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
