## Unreleased

### Added
- Initial scaffold: Vapor server, Auth0 Authorization Code login flow (`/auth/login`,
  `/auth/callback`, `/auth/logout`), shared session establishment (Redis-backed, `sub`/name/
  email/roles verified via `users-api`'s `/authz/check`), Docker image build, and Kubernetes
  manifests (including this app's own dedicated Redis instance).
