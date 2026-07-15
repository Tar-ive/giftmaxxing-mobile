# Password storage audit

The app's production authentication providers are Amazon Cognito (iOS email/password) and Clerk (web). The app does not store provider passwords; it stores only provider/session tokens in the iOS Keychain. No plaintext, MD5, or SHA-1 password storage was found in the repository.

`infra/src/auth/password-service.mjs` is the service for any legacy or local account records: signup and password changes use bcrypt with 12 rounds, bcrypt verification is constant-time, and legacy plaintext/MD5/SHA-1 values are upgraded only after a successful login. `migrate-password-on-login.mjs` performs an atomic, compare-and-set DynamoDB update for the authenticated user. It is intentionally not connected to Cognito, because Cognito owns and hashes those passwords and does not expose its password database for migration.

Do not add passwords to the `users` profile table. If a legacy account store is reintroduced, call `migratePasswordOnLogin` in that store's login handler and never log request bodies, password arguments, or password hashes.
