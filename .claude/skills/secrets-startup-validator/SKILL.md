---
name: secrets-startup-validator
description: Fail-closed @PostConstruct validators (AuthCookieValidator, AlbOidcPropertiesValidator, SecretsValidator) that fail at startup on misconfiguration instead of trusting the first runtime cookie/JWT/s...
origin: ECC
triggers: PostConstruct validator, startup validation, fail fast, fail closed, secrets validator, missing env var, configuration validation, AuthCookieValidator, AlbOidcPropertiesValidator, CloudSecretsValidator, OIDC issuer, AWS Secrets Manager
paths:
  - "**/*.java"
  - "**/*.kt"
---
# Secrets / Configuration Startup Validators

Misconfigured secrets, missing env vars, malformed OIDC URLs, blank cookie attributes — these are **deploy-time** errors. They almost always boot cleanly, pass the smoke test (which doesn't exercise the affected code path), and only surface hours or days later as "auth flow broken" or "magic link never arrives" or "every user session is silently broken".

The fix is to validate at **`@PostConstruct` / `ApplicationStartedEvent`**, before the first request. A misconfigured deploy fails to start. A correctly-configured deploy boots. There is no third state.

## When to use

- Any property bound from an env var that is required for production but absent in dev (`OIDC_ISSUER_URL`, `WHATSAPP_APP_SECRET`, `SENDGRID_API_KEY`, `AWS_SECRETS_MANAGER_ARN`).
- Any cookie / session / token attribute combination where invalid combinations boot cleanly but break browser behavior (`SameSite=None` without `Secure`, `__Secure-` prefix without `Secure`).
- Any URL / ARN / region string consumed by a third-party SDK where the SDK silently retries on a malformed value before timing out.
- Any "default placeholder" used during dev (`bootstrap-jwt-secret`, `change-me`, `dev-only-key`) that must NOT reach production.

## When NOT to use

- Optional configuration with a documented safe default. Validating the default just adds noise.
- Properties that genuinely don't matter until first use AND the first-use error message is already great. (Rare. Most "first use" errors are stack traces buried under five layers of framework.)
- Test fixtures. Validators MUST be opt-out via property, not Spring profile.

## The pattern

### Three failure modes the validator must catch

1. **Missing required env var.** Boots cleanly with empty string; first request fails far from the deploy.
2. **Malformed value.** Looks set, isn't valid (URL parse fails, ARN regex fails, base64 decode fails, length wrong).
3. **Invalid combination.** Each property valid alone, the pair invalid (`SameSite=None` + `Secure=false` is the textbook example).

### Validator shape

```java
@Component
@ConditionalOnProperty(prefix = "app.auth.cookie", name = "validate",
        havingValue = "true", matchIfMissing = true)        // on by default
class AuthCookieValidator {

    private static final Set<String> KNOWN_SAME_SITE_VALUES = Set.of("strict", "lax", "none");
    private static final String SECURE_PREFIX = "__Secure-";

    private final String accessCookieName;
    private final @Nullable String sameSite;
    private final boolean secure;

    AuthCookieValidator(
            @Value("${app.auth.cookie.access-name:" + AuthCookieService.ACCESS_TOKEN_COOKIE + "}") String accessCookieName,
            @Value("${app.auth.cookie.same-site:}") @Nullable String sameSite,
            @Value("${app.auth.cookie.secure:true}") boolean secure) {
        this.accessCookieName = accessCookieName;
        this.sameSite = sameSite;
        this.secure = secure;
    }

    @PostConstruct
    void validate() {
        if (sameSite == null || sameSite.isBlank()) {
            throw new IllegalStateException(
                "app.auth.cookie.same-site must be configured (Strict, Lax, or None) — "
                + "blank values produce non-deterministic browser behavior.");
        }
        String normalized = sameSite.toLowerCase(Locale.ROOT);
        if (!KNOWN_SAME_SITE_VALUES.contains(normalized)) {
            throw new IllegalStateException(
                "app.auth.cookie.same-site must be one of Strict, Lax, None — got '" + sameSite + "'.");
        }
        if ("none".equals(normalized) && !secure) {
            throw new IllegalStateException(
                "app.auth.cookie.same-site=None requires app.auth.cookie.secure=true. "
                + "Modern browsers refuse to send SameSite=None cookies without Secure; the resulting deploy "
                + "boots cleanly but every user session is silently broken.");
        }
        if (accessCookieName.startsWith(SECURE_PREFIX) && !secure) {
            throw new IllegalStateException(
                "Cookie name '" + accessCookieName + "' carries the " + SECURE_PREFIX
                + "prefix, which requires app.auth.cookie.secure=true.");
        }
    }
}
```

Three rules in the message body:
1. Name the property exactly so a Ctrl-F on the runbook hits.
2. State why the deploy will fail at runtime.
3. State the corrective action.

### Validator companion: aggregated secrets

For a multi-secret bundle, prefer `@EventListener(ApplicationStartedEvent.class)` so the validation runs after the entire context is built (handles inter-bean dependencies cleanly), and **collect** all errors before throwing:

```java
@Component
@ConditionalOnProperty(prefix = "app.security", name = "fail-fast-on-missing-secrets",
        havingValue = "true", matchIfMissing = true)
class SecretsValidator {

    @EventListener(ApplicationStartedEvent.class)
    void validateSecrets() {
        StringBuilder errors = new StringBuilder();
        if (this.oidcIssuerUri.isBlank()) errors.append("  - OIDC_ISSUER_URL must be set\n");
        if (this.whatsappAppSecret.isBlank()) errors.append("  - WHATSAPP_APP_SECRET must be set\n");
        if (this.sendGridApiKey.isBlank() && this.resendApiKey.isBlank()) {
            errors.append("  - At least one of SENDGRID_API_KEY or RESEND_API_KEY must be set\n");
        }
        if (!errors.isEmpty()) {
            throw new IllegalStateException(
                "FATAL: managed runtime requires the following secrets:\n" + errors
                + "Set these environment variables before starting the application.");
        }
    }
}
```

Collecting all errors in a single `IllegalStateException` lets the operator fix everything in one deploy cycle, instead of redeploying once per missing secret.

## Common gotchas / variants

- **Validator gated on Spring profile.** Prefer `@ConditionalOnProperty` with `matchIfMissing=true`. Tests opt out by property override, not by activating a profile.
- **Cookie length / base-64 decode.** A "JWT secret must be at least 32 bytes" check belongs in the validator, not in the first JWT-issuance call site.
- **AWS Secrets Manager ARN.** Validate format `arn:aws:secretsmanager:<region>:<account>:secret:<name>-<6 chars>` — a typo'd ARN fails on the first secret fetch, not at startup.
- **OIDC issuer URL.** Validate `URI.create(issuer).isAbsolute()` and that `https://` is present. The OIDC discovery endpoint will silently 404 otherwise.
- **`@PostConstruct` ordering across validators is not guaranteed.** Use `@EventListener(ApplicationStartedEvent.class)` for cross-validator orchestration.
- **Default placeholder secret.** Pair the validator with a check that the value is NOT the dev default (`DEFAULT_BOOTSTRAP_JWT_SECRET`). A deploy that forgot to override but happened to set the env var to the placeholder is more dangerous than a deploy that left it empty.

## Verification

```java
@Test
void should_fail_startup_when_samesite_none_combined_with_secure_false() {
    AuthCookieValidator validator = new AuthCookieValidator("__Secure-app_at", "None", false);
    assertThatThrownBy(validator::validate)
        .isInstanceOf(IllegalStateException.class)
        .hasMessageContaining("SameSite=None")
        .hasMessageContaining("Secure");
}

@Test
void validator_does_not_register_when_validate_property_is_false() {
    new ApplicationContextRunner()
        .withUserConfiguration(AuthCookieValidator.class)
        .withPropertyValues("app.auth.cookie.same-site=None",
                            "app.auth.cookie.secure=false",
                            "app.auth.cookie.validate=false")
        .run(context -> {
            assertThat(context.getStartupFailure()).isNull();
            assertThat(context).doesNotHaveBean(AuthCookieValidator.class);
        });
}

@Test
void validator_registers_by_default_and_fails_fast_on_invalid_settings() {
    new ApplicationContextRunner()
        .withUserConfiguration(AuthCookieValidator.class)
        .withPropertyValues("app.auth.cookie.same-site=None",
                            "app.auth.cookie.secure=false")
        .run(context -> {
            assertThat(context.getStartupFailure()).rootCause()
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("SameSite=None");
        });
}
```

`ApplicationContextRunner` is the right tool: it spins up a minimal context, lets the validator fire, and exposes `getStartupFailure()` so you can assert on the root cause without polluting the runtime.

## Node.js / TypeScript equivalent

The Node ecosystem solves this with schema validation against `process.env` at app boot. Two strong options: `zod` (TypeScript-native, great error messages) and `joi` (older, more features). Both throw at startup if required env vars are missing or malformed.

### zod (preferred for TS)

```typescript
// src/config/env.ts
import { z } from 'zod';

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']),
  DATABASE_URL: z.string().url(),
  OIDC_ISSUER_URL: z.string().url(),
  WHATSAPP_APP_SECRET: z.string().min(32, 'must be at least 32 chars'),
  AUTH_COOKIE_SAME_SITE: z.enum(['Strict', 'Lax', 'None']),
  AUTH_COOKIE_SECURE: z.coerce.boolean(),
}).refine(
  (env) => !(env.AUTH_COOKIE_SAME_SITE === 'None' && !env.AUTH_COOKIE_SECURE),
  { message: 'AUTH_COOKIE_SAME_SITE=None requires AUTH_COOKIE_SECURE=true' }
);

// Parse at module-load time. Throws on misconfig — boot fails.
export const env = envSchema.parse(process.env);
```

Importing `env` from anywhere in the app gives you a strongly-typed config object. The `.refine()` clause encodes invariants (the SameSite=None+Secure=false trap, etc.).

### joi (legacy but widespread)

```javascript
const Joi = require('joi');

const schema = Joi.object({
  DATABASE_URL: Joi.string().uri().required(),
  WHATSAPP_APP_SECRET: Joi.string().min(32).required(),
}).unknown(true);

const { error, value } = schema.validate(process.env);
if (error) {
  throw new Error(`FATAL: env misconfigured: ${error.message}`);
}
module.exports = value;
```

### Aggregate multi-secret bundle

For "validate everything at once and report all errors":

```typescript
const errors: string[] = [];
if (!process.env.OIDC_ISSUER_URL) errors.push('OIDC_ISSUER_URL must be set');
if (!process.env.WHATSAPP_APP_SECRET) errors.push('WHATSAPP_APP_SECRET must be set');
if (!process.env.SENDGRID_API_KEY && !process.env.RESEND_API_KEY) {
  errors.push('At least one of SENDGRID_API_KEY or RESEND_API_KEY must be set');
}
if (errors.length > 0) {
  throw new Error(`FATAL: missing secrets:\n  - ${errors.join('\n  - ')}`);
}
```

### Differences from Java

- Schema is the source of truth; the validator IS the parser.
- TypeScript inference gives `env` a typed shape automatically — no `@Value` injection.
- `dotenv-safe` (npm) checks `.env` against `.env.example` at boot — useful for catching missing-but-required keys.
- No Spring `@PostConstruct` ordering issues; module-load order is controlled by import statements.

## References

- Implementation:
- Spring `org.springframework.boot.test.context.runner.ApplicationContextRunner`
- Companion rule: `no-custom-spring-profiles.md` — validators are gated by property, not profile
