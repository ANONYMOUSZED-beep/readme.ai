# ADR 0004 — Authentication: Firebase Identity, Stateless JWT Verification

- **Status:** Accepted
- **Date:** Sprint 1.0

## Context

ReadMe.ai needs secure user identity. Firebase Authentication (Google Sign-In)
was chosen as the identity provider. The backend must trust no client input and
validate identity on every request, while keeping the internal data model
independent of the provider.

## Decisions

1. **Internal user keyed to the Firebase UID.** The backend stores its own
   `User` row (internal UUID primary key) linked by `firebase_uid`. All future
   domain data references the internal UUID, so the identity provider can change
   without rewriting relationships.

2. **Stateless verification on every request.** The client sends the Firebase ID
   token as a `Bearer` token; the backend verifies it on each request. There is
   no server-side session store, so "logout" is a client concern and the server
   `/logout` endpoint is a stateless acknowledgement.

3. **Token verification behind a `TokenVerifier` abstraction.** The production
   `FirebaseTokenVerifier` validates Google's RS256-signed ID tokens against
   Google's published X.509 certificates (checking `aud`/`iss`/`exp`), caching
   the certs per their `Cache-Control`. This mirrors ADR 0003's principle of
   quarantining external dependencies behind a stable contract, and lets tests
   inject a fake verifier (no network, no Firebase).

   PyJWT + cryptography were chosen over the full `firebase-admin` SDK: lighter
   weight, no service-account bootstrapping, and only the public project id is
   required.

4. **Just-in-time provisioning.** The internal user is created on the first
   authenticated request and its profile/last-login refreshed on subsequent
   requests.

5. **Flutter: Firebase config via `--dart-define`, not a committed file.** No
   `firebase_options.dart` with credentials is committed. Configuration is
   supplied at build time, keeping secrets out of the repository and allowing
   per-environment configuration. The client's `AuthRepository` interface hides
   Firebase from the application/presentation layers.

## Consequences

- The backend needs network access to Google's cert endpoint (cached).
- Real Google Sign-In requires the team's Firebase project and platform OAuth
  setup; see `apps/mobile/README.md`. The code is provider-agnostic above the
  data layer, so swapping providers is localized.
- Revocation is bounded by token lifetime (stateless). Acceptable for this app;
  revisit if immediate server-side revocation becomes a requirement.
