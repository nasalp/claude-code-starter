---
name: pii-log-scrubbing
description: Scrub PII from logs at the formatter — domain-only emails, partial phone redaction, body redaction in webhook/auth filters. ListAppender regression tests fail when PII reappears.
origin: ECC
triggers: PII, log scrubbing, email logging, phone redaction, ListAppender, ILoggingEvent, AlbJwtFilter, ControllerAdvice, log redaction, GDPR, sensitive data in logs, domainOf
paths:
  - "**/*.java"
  - "**/*.kt"
  - "**/*.ts"
  - "**/*.py"
---
# PII Log Scrubbing

Logs are durable, replicated, sometimes shipped to third-party SaaS, frequently grep-able by anyone with read access on the aggregator. They are the wrong place for PII. The mistake is almost never deliberate — it is a `log.warn("auth failed for {}", email)` that survives review because the local-part is necessary for "debugging".

It isn't. The domain is enough to triage; the local-part is the user's identifier.

This skill codifies the scrub-at-the-formatter pattern with regression tests that fail loudly when PII reappears.

## When to use

- Any auth filter or webhook handler that touches user-identifying input (`@RequestBody`, `Principal`, JWT claims, OIDC ID tokens).
- Any `@RestControllerAdvice` / `GlobalExceptionHandler` that logs the exception's message — Spring's `MethodArgumentNotValidException` and `HttpMessageNotReadableException` echo the request body verbatim into the log.
- Audit / activity feeds that emit "user X did Y".
- Any structured-logging field named `email`, `phone`, `address`, `ssn`, `dob`, `iban`, `card`.

## When NOT to use

- Pure infrastructure logs (request id, latency ms, HTTP status, route). No scrub needed.
- Test fixtures that use clearly-fake values (`test-user@example.com`, `+15555550100`). Don't over-scrub; the test is signal.
- Stack traces of internal exceptions that do not carry user input. Scrub the *message*; keep the trace.

## The pattern

Scrub at the **formatter / log-call boundary**. A regex-based logback `Filter` is a fallback for legacy code; new code should call helpers explicitly so the redaction is visible at the call site.

### Email — domain only

```java
private static String domainOf(String email) {
    int at = email.lastIndexOf('@');
    return (at >= 0 && at < email.length() - 1)
        ? email.substring(at + 1)
        : "<no-domain>";
}

// Use:
log.warn("ALB OIDC: unknown email at domain {} — rejecting (no auto-provision)", domainOf(email));
```

The logged line carries `domain=example.com` — operators can still answer "an `@somecorp.com` user hit the auth filter" without storing the user's identifier.

`<no-domain>` (sentinel for malformed inputs) prevents the obvious bypass: `email = "no-at-sign"` would otherwise log the entire string under the heading "domain".

### Phone — partial redaction, keep last-4

```java
static String redactPhone(String e164) {
    if (e164 == null || e164.length() < 4) return "<phone>";
    String last4 = e164.substring(e164.length() - 4);
    int countryEnd = e164.startsWith("+") ? 3 : 2;
    String country = e164.substring(0, Math.min(countryEnd, e164.length()));
    return country + " *** ***-" + last4;
}
// "+48 123 456-7890" -> "+48 *** ***-7890"
```

Last-4 is enough for support correlation; the full number is enough to deanonymize against any data broker.

### Webhook / `@RestControllerAdvice` body redaction

The classic leak: a global handler logs the failing request body to "help debug 400s". The body contains the email, password (yes, really), or full PII payload.

```java
// ❌ NEVER
@ExceptionHandler(MethodArgumentNotValidException.class)
ProblemDetail badRequest(MethodArgumentNotValidException ex, HttpServletRequest req) {
    String body = readBody(req);                         // contains user PII
    log.warn("validation failed body={} errors={}", body, ex.getMessage());
    return ProblemDetails.create(BAD_REQUEST, "VALIDATION_ERROR", ex.getMessage(), req);
}

// ✅ Log structure, not contents
@ExceptionHandler(MethodArgumentNotValidException.class)
ProblemDetail badRequest(MethodArgumentNotValidException ex, HttpServletRequest req) {
    List<String> failedFields = ex.getBindingResult().getFieldErrors().stream()
        .map(FieldError::getField).toList();
    log.warn("validation failed path={} fields={}", req.getRequestURI(), failedFields);
    return ProblemDetails.create(BAD_REQUEST, "VALIDATION_ERROR", "Invalid request", req);
}
```

`ex.getMessage()` itself can contain field values — do NOT log it as-is.

## Common gotchas / variants

- **`log.error("{}", request)` calls `request.toString()` reflectively.** Whatever `toString()` exposes ends up in the log. Override `toString()` on every request DTO to emit a redacted form, or never `{}`-log full DTOs.
- **MDC contains a JWT or session token.** A `MDC.put("user", jwt)` followed by anything that prints MDC leaks the token. Put the user *id* in MDC, never the credential.
- **Spring Boot 3.x `logging.level.web=DEBUG` dumps full headers and bodies** including `Authorization`. Do not enable DEBUG on `web` or `org.springframework.security` in production.
- **`HttpServletRequest::getQueryString` includes tokens** if the API ever accepts `?token=`. Strip on log.
- **Structured logging (logstash encoder).** A field named `email` in a JSON event is the same leak as a string substitution. The redaction must run before the field is emitted.
- **Cardinality.** Logging full email addresses also blows up Loki / OpenSearch label cardinality and metric label dimensions. Domain-only is also operationally cheaper.
- **Stack traces.** A `BadCredentialsException("Bad credentials for user@example.com")` carries the email in the trace. Throw with a non-PII message; log the structured field separately.

## Verification

Attach a Logback `ListAppender` and assert PII does NOT appear in any captured event:

```java
@BeforeEach
void attachLogCapture() {
    albJwtFilterLogger = (Logger) LoggerFactory.getLogger(AlbJwtFilterImpl.class);
    appender = new ListAppender<>();
    appender.start();
    albJwtFilterLogger.addAppender(appender);
}

@Test
void unknown_email_log_redacts_local_part_and_keeps_domain() throws Exception {
    String revealingLocalPart = "secret-username-1234";
    String email = revealingLocalPart + "@example.com";

    when(verifier.extractEmail("any-token")).thenReturn(email);
    AlbJwtFilterImpl filter = new AlbJwtFilterImpl(securityContext, lookup, verifier);

    MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/v1/test");
    request.addHeader("x-amzn-oidc-data", "any-token");

    filter.doFilterInternal(request, new MockHttpServletResponse(), new MockFilterChain());

    boolean leakedLocalPart = appender.list.stream()
        .map(ILoggingEvent::getFormattedMessage)
        .anyMatch(msg -> msg.contains(revealingLocalPart));
    assertThat(leakedLocalPart).as("log line must NOT include the email local part — PII leak").isFalse();

    boolean domainLogged = appender.list.stream()
        .map(ILoggingEvent::getFormattedMessage)
        .anyMatch(msg -> msg.contains("example.com"));
    assertThat(domainLogged).as("log line should include the email domain").isTrue();
}
```

The `assertThat(leakedLocalPart).isFalse()` is the regression guard. A future "improvement" that adds `log.info("user {} authenticated", email)` will turn this test red.

The Wave 7 hardening also flipped the unknown-email path from auto-VIEWER (fail-open) to 401 (fail-closed). The log line is now `WARN`, not `INFO`, and explicit: `"unknown email at domain {} — rejecting (no auto-provision)"`. Always pair PII scrubbing with a fail-closed authn path; a domain-only log line on a fail-open auth filter is still a security regression.

## Node.js / TypeScript equivalent

### Pino — built-in `redact:` config

Pino is the canonical choice. Its `redact` option takes JSON-pointer paths and replaces matching values with `[Redacted]`:

```typescript
import pino from 'pino';

const log = pino({
  redact: {
    paths: [
      'req.headers.authorization',
      'req.headers.cookie',
      '*.email',
      '*.phone',
      '*.password',
      'req.body.password',
      'res.body.token',
    ],
    censor: '[Redacted]',
    remove: false,  // keep the key, redact the value
  },
});

log.warn({ user: { email: 'alice@example.com', phone: '+48123456789' } }, 'login attempt');
// outputs: {... "user": {"email": "[Redacted]", "phone": "[Redacted]"} ...}
```

For domain-only logging:

```typescript
function domainOf(email: string): string {
  const at = email.lastIndexOf('@');
  return at >= 0 && at < email.length - 1 ? email.slice(at + 1) : '<no-domain>';
}

log.warn({ domain: domainOf(email) }, 'unknown email at domain — rejecting');
```

### Winston — custom format

Winston needs more boilerplate but is widely deployed:

```typescript
import { createLogger, format, transports } from 'winston';

const PII_KEYS = /^(email|phone|address|ssn|password|token)$/i;

const redactFormat = format((info) => {
  function walk(obj: any) {
    if (obj == null || typeof obj !== 'object') return obj;
    for (const key of Object.keys(obj)) {
      if (PII_KEYS.test(key)) obj[key] = '[Redacted]';
      else walk(obj[key]);
    }
    return obj;
  }
  return walk(info);
});

const logger = createLogger({
  format: format.combine(redactFormat(), format.json()),
  transports: [new transports.Console()],
});
```

### Body redaction in Express error handlers

```typescript
app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
  // ❌ NEVER: log.error({ body: req.body, err })
  // ✅ Log structure, not contents:
  log.error({
    path: req.path,
    fields: Object.keys(req.body || {}),
    err: err.message,
  }, 'request failed');
  res.status(500).json({ error: 'internal_error' });
});
```

### Regression test (Vitest)

```typescript
import { sink } from 'pino-test';

it('domain-only log keeps domain, redacts local-part', async () => {
  const stream = sink();
  const log = pino({ redact: { paths: ['*.email'], censor: '[Redacted]' } }, stream);

  log.warn({ user: { email: 'secret-username@example.com' } }, 'reject');

  for await (const record of stream) {
    expect(JSON.stringify(record)).not.toContain('secret-username');
    expect(JSON.stringify(record)).toContain('[Redacted]');
    break;
  }
});
```

### Differences from Java

- Pino's `redact:` is configuration, not code — terser than Logback's regex Filter.
- `req.body` (Express) is the analogue of `MethodArgumentNotValidException` — same leak class, same fix.
- No MDC analogue; use Pino child loggers (`log.child({ requestId })`) for context.
- Sentry / DataDog / Honeycomb integrations have their own scrubbers — check them too, not just the local logger.

## References

- Implementation:
- Spring `org.springframework.web.bind.MethodArgumentNotValidException` — most common leak surface
- Logback `ch.qos.logback.core.read.ListAppender` for tests
