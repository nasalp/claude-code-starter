---
name: alb-oidc-auth
description: End-to-end pattern for AWS ALB-fronted OIDC authentication — CDK Listener authenticateOidc + JWT signature verification against the regional ALB key + Spring filter that grants role-based authorities.
origin: ECC
triggers: x-amzn-oidc-data, ALB OIDC, authenticateOidc, AlbJwtFilter, AlbOidcVerifier, public-keys.auth.elb, Google Workspace SSO, hd parameter, OncePerRequestFilter, SecurityContextAccessor, AlbSecurityConfig
paths:
  - "**/*.java"
  - "**/*.ts"
---
# ALB OIDC Authentication

## When to use

You are deploying a Spring Boot service behind an AWS Application Load
Balancer that handles OIDC sign-in (Google Workspace SSO, Okta, Auth0,
or any OIDC provider). The ALB injects `x-amzn-oidc-data` (a Base64-
encoded ES256-signed JWT) into every request. Your service has to:

1. Stand up the ALB with OIDC configured (CDK).
2. Verify the ALB-issued JWT is genuine — signature, issuer, audience,
   expiry. Otherwise an attacker who reaches the application directly
   can forge a header.
3. Map the verified email to an application role and grant Spring
   Security authorities.

Three sections below — A (infrastructure / CDK), B (signature
verification), C (application filter) — are the three layers you need
to ship together. Skipping B is the most common mistake; "ALB is a
trusted proxy, the header cannot be spoofed by clients" is wrong as
soon as the application is reachable on the VPC private subnet by
anything other than the ALB.

## When NOT to use

- The application uses Cognito User Pools or another self-managed
  IdP — those use their own SDKs.
- You are not on AWS. Ingress/auth on Cloud Run, Cloudflare Access,
  or Azure App Service have their own header conventions.
- The service is dev-only and runs behind a single trusted operator
  network. You may still want some auth, but ALB OIDC is overkill.
- Local development. Use a `@ConditionalOnProperty` dev filter (see
  Section C "Dev mode" below) — never run ALB verification against
  fake headers locally.

## The pattern

### Section A — Infrastructure (AWS CDK)

The ALB listener wraps every action in `authenticateOidc`. Authentication
happens before any traffic reaches the target group:

```typescript
// lib/stacks/platform-stack.ts

/**
 * Wraps `next` with Google OIDC authentication if configured for
 * this env. Called by both the default 404 action and each service's
 * listener rule, ensuring every request is authenticated regardless
 * of which rule matches. Returns `next` unchanged if Google OIDC is
 * not configured.
 */
public buildAuthAction(next: elbv2.ListenerAction): elbv2.ListenerAction {
  if (!this.googleOidc || !this.googleClientSecret) return next;

  const extraParams: Record<string, string> = {};
  if (this.googleOidc.allowedDomain) {
    // 'hd' = Google Workspace hosted-domain enforcement.
    // ALB passes it to /authorize so the user can only sign in with
    // an account in that workspace (e.g. @example.com).
    extraParams['hd'] = this.googleOidc.allowedDomain;
  }

  return elbv2.ListenerAction.authenticateOidc({
    issuer:                 'https://accounts.google.com',
    authorizationEndpoint:  'https://accounts.google.com/o/oauth2/v2/auth',
    tokenEndpoint:          'https://oauth2.googleapis.com/token',
    userInfoEndpoint:       'https://openidconnect.googleapis.com/v1/userinfo',
    clientId:               this.googleOidc.clientId,
    clientSecret:           this.googleClientSecret.secretValueFromJson('clientSecret'),
    scope:                  'openid email profile',
    authenticationRequestExtraParams: extraParams,
    sessionTimeout:         cdk.Duration.hours(1),
    next,
  });
}
```

The client secret is loaded from Secrets Manager via
`secretsmanager.Secret.fromSecretCompleteArn` so the CDK code never
sees the literal value:

```typescript
this.googleClientSecret = secretsmanager.Secret.fromSecretCompleteArn(
  this, 'GoogleOidcClientSecret', envConfig.googleOidc.clientSecretArn);
```

`buildAuthAction` is the single seam. Every listener rule in
`service-stack.ts` calls it, so a service that forgets to opt in still
gets authenticated:

```typescript
listener.addAction('FixedRule', {
  priority: 100,
  conditions: [elbv2.ListenerCondition.hostHeaders([host])],
  action:    platform.buildAuthAction(
                 elbv2.ListenerAction.forward([targetGroup])),
});
listener.setDefaultAction(
    platform.buildAuthAction(elbv2.ListenerAction.fixedResponse(404)));
```

### Section B — Signature Verification

The ALB signs `x-amzn-oidc-data` with a per-region rotating ES256
private key. The matching public key is served at
`https://public-keys.auth.elb.<region>.amazonaws.com/<kid>`. The
verifier:

1. Reads the JWT header to extract `kid`.
2. Fetches the public key from the regional endpoint, cached in
   Caffeine.
3. Verifies the signature with Nimbus `JWSVerifier` (ES256 only).
4. Validates `iss`, `exp`, `aud`, and `signer` claims.
5. Only after all five checks pass, returns the `email` claim.

```java
@Component
class AlbOidcVerifier {

    private final AlbOidcKeyProvider keyProvider;
    private final AlbOidcProperties props;

    String extractEmail(String albOidcDataHeader) {
        SignedJWT jwt = parse(albOidcDataHeader);
        JWSHeader header = jwt.getHeader();

        // Defense in depth: reject alg=none and HS256 BEFORE looking
        // up the key. Nimbus also rejects, but the explicit pre-check
        // shortens the audit trail.
        if (header.getAlgorithm() == null
                || !JWSAlgorithm.ES256.equals(header.getAlgorithm())) {
            throw new AlbAuthException("Unsupported alg: "
                + header.getAlgorithm());
        }
        String kid = header.getKeyID();
        if (kid == null || kid.isBlank()) {
            throw new AlbAuthException("Missing kid header");
        }

        ECPublicKey key = keyProvider.publicKeyFor(kid);
        try {
            if (!jwt.verify(new ECDSAVerifier(key))) {
                throw new AlbAuthException("Signature verification failed");
            }
        } catch (JOSEException e) {
            throw new AlbAuthException("Signature verification error", e);
        }

        JWTClaimsSet claims = jwt.getJWTClaimsSet();
        if (!props.expectedIssuer().equals(claims.getIssuer())) {
            throw new AlbAuthException("Issuer mismatch: " + claims.getIssuer());
        }
        if (claims.getExpirationTime() == null
                || claims.getExpirationTime().toInstant().isBefore(Instant.now())) {
            throw new AlbAuthException("Token expired");
        }
        if (!claims.getAudience().contains(props.expectedAudience())) {
            throw new AlbAuthException("Audience mismatch");
        }
        // signer claim is the ARN of the ALB; pin it.
        if (!props.expectedSigner().equals(claims.getStringClaim("signer"))) {
            throw new AlbAuthException("Signer mismatch");
        }
        return claims.getStringClaim("email");
    }
}
```

The key provider uses Caffeine — bounded cache, 24h TTL, recordStats:

```java
@Component
class AlbOidcKeyProvider {

    private final RestClient http;
    private final AlbOidcProperties props;
    private final Cache<String, ECPublicKey> cache;

    AlbOidcKeyProvider(RestClient.Builder builder, AlbOidcProperties props,
                       MeterRegistry registry) {
        this.http  = builder.build();
        this.props = props;
        this.cache = Caffeine.newBuilder()
            .maximumSize(64)            // a handful of kids in prod
            .expireAfterWrite(Duration.ofHours(24))
            .recordStats()
            .build();
        CaffeineCacheMetrics.monitor(registry, this.cache, "alb_oidc_keys");
    }

    ECPublicKey publicKeyFor(String kid) {
        return cache.get(kid, this::fetch);
    }

    private ECPublicKey fetch(String kid) {
        String url = props.keyEndpointBaseUrl() + "/" + kid;
        try {
            String pem = http.get().uri(url).retrieve().body(String.class);
            return parseEcPublicKey(pem);
        } catch (RestClientException | GeneralSecurityException e) {
            throw new AlbAuthException("Public key fetch failed: " + kid, e);
        }
    }
}
```

A startup gate enforces deployment-time invariants — region, expected
issuer, audience, signer must all be set:

```java
@Component
class AlbOidcPropertiesValidator {

    @EventListener(ApplicationReadyEvent.class)
    void validate(AlbOidcProperties props) {
        require(props.region(),           "alb.oidc.region");
        require(props.expectedIssuer(),   "alb.oidc.expected-issuer");
        require(props.expectedAudience(), "alb.oidc.expected-audience");
        require(props.expectedSigner(),   "alb.oidc.expected-signer");
    }
    private static void require(String v, String name) {
        if (v == null || v.isBlank()) {
            throw new IllegalStateException(name + " must be set");
        }
    }
}
```

### Section C — Application Filter

`OncePerRequestFilter` reads the verified email, looks up the role
from the application database, and grants `ROLE_USER` plus
`ROLE_<role>`:

```java
@Component
@ConditionalOnProperty(prefix = "app.security.dev-auth",
                       name = "enabled", havingValue = "false",
                       matchIfMissing = true)
class AlbJwtFilter extends OncePerRequestFilter {

    static final String ALB_OIDC_HEADER = "x-amzn-oidc-data";
    private final SecurityContextAccessor securityContext;
    private final AppUserRepository userRepository;
    private final AlbOidcVerifier verifier;

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                     HttpServletResponse response,
                                     FilterChain chain)
            throws ServletException, IOException {
        String token = request.getHeader(ALB_OIDC_HEADER);
        if (token == null || token.isBlank()) {
            chain.doFilter(request, response);
            return;
        }
        try {
            String email = verifier.extractEmail(token);
            var role = userRepository.findRoleByEmail(email);
            if (role.isEmpty()
                    && userRepository.existsInactiveByEmail(email)) {
                securityContext.clearContext();
                response.setStatus(HttpServletResponse.SC_FORBIDDEN);
                return;
            }
            Role effective = role.orElse(Role.VIEWER);
            var auth = new UsernamePasswordAuthenticationToken(email, null,
                List.of(new SimpleGrantedAuthority("ROLE_USER"),
                        new SimpleGrantedAuthority("ROLE_" + effective.name())));
            securityContext.setAuthentication(auth);
            chain.doFilter(request, response);
        } catch (AlbAuthException ex) {
            log.warn("ALB OIDC authentication failed: {}",
                String.valueOf(ex.getMessage()).replaceAll("[\\r\\n]", ""));
            securityContext.clearContext();
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        }
    }
}
```

`SecurityContextAccessor` is a one-method interface that wraps
`SecurityContextHolder` so tests don't have to reach into Spring
Security's static state:

```java
interface SecurityContextAccessor {
    void setAuthentication(Authentication auth);
    void clearContext();
}
```

The security config registers the filter before
`UsernamePasswordAuthenticationFilter`:

```java
@Configuration
@EnableWebSecurity
@EnableMethodSecurity
@ConditionalOnProperty(prefix = "app.security.dev-auth",
                       name = "enabled", havingValue = "false",
                       matchIfMissing = true)
class AlbSecurityConfig {
    @Bean
    SecurityFilterChain albFilterChain(HttpSecurity http,
                                       AlbJwtFilter albJwtFilter)
            throws Exception {
        return http.securityMatcher("/**")
            .headers(h -> h.httpStrictTransportSecurity(s -> s
                .maxAgeInSeconds(31536000).includeSubDomains(true)))
            .csrf(c -> c.disable())
            .sessionManagement(s -> s
                .sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(a -> a
                .requestMatchers("/actuator/health/**", "/actuator/info").permitAll()
                .anyRequest().authenticated())
            .addFilterBefore(albJwtFilter,
                UsernamePasswordAuthenticationFilter.class)
            .build();
    }
}
```

**Dev mode.** Use `@ConditionalOnProperty`, NOT `@Profile`. A
`DevUserFilter` activates when `app.security.dev-auth.enabled=true`
(set by `dev.sh`); ALB filter activates by default. No profiles, no
combinatorial config matrix.

## Common gotchas / variants

- **Don't trust the header without signature verification.** A "trust
  the proxy" implementation works until the application port is
  reachable from anything other than the ALB — VPC peer, jump host,
  misconfigured security group. Verify the JWT, always.
- **`alg=none` and HS256 must be rejected explicitly.** Nimbus rejects
  them with the right configuration, but make the rejection visible
  in your code so an audit reads cleanly.
- **`iss`, `exp`, `aud`, and `signer` are all required claims.** ALB
  signs each with the ARN of the load balancer. Pin all four; missing
  any one is a CVE in waiting.
- **`hd` (hosted domain) is enforced by the IdP, not the ALB.** Setting
  `hd=example.com` on the `/authorize` request makes Google Workspace
  reject sign-ins from other domains. Without `hd`, any Google account
  passes the OIDC step; the application must catch unknown emails
  itself (the `existsInactiveByEmail` branch above).
- **Cache the public key per `kid`, not by URL.** ALB rotates keys
  with new `kid`s; old keys remain reachable until expiry. A 24h TTL
  is generous; AWS rotates infrequently.
- **`SecurityContextAccessor` is mandatory for testability.** Static
  `SecurityContextHolder.getContext()` calls are forbidden in
  controllers; the same applies to filters when you want unit tests.
  See `controllers.md`.
- **OncePerRequestFilter, not Filter.** Filters fire on forwards and
  includes; the once-per-request guard prevents double-authenticating
  on async dispatches.

## Verification

- **CDK unit test** (`platform-stack.test.ts`): assert the listener has
  an `AuthenticateOidcConfig` action with the expected issuer,
  client-secret reference, and `hd` extra param when configured.
- **Verifier tests** (Nimbus-forged tokens):
  - Valid ES256 → accepted
  - Wrong key → rejected
  - `alg=none` → rejected
  - `alg=HS256` → rejected
  - Expired `exp` → rejected
  - Wrong `iss` → rejected
  - Missing `kid` → rejected
- **Key-provider tests** (WireMock):
  - First fetch hits network; second fetch is served from cache
  - 404 / timeout surfaces `AlbAuthException`
  - Cache eviction after `expireAfterWrite` triggers re-fetch
- **Filter tests** (MockMvc):
  - No header → chain proceeds (will be 401 later from the security
    config, but the filter itself is silent)
  - Bad header → `clearContext` + 401
  - Verified email + known role → grants `ROLE_USER, ROLE_<role>`
  - Verified email + unknown role → grants `ROLE_USER, ROLE_VIEWER`
  - Verified email + inactive user → 403
- **Properties validator test**: any of region / issuer / audience /
  signer blank → application context fails to start.

## Node.js / TypeScript equivalent

Section A (CDK) is already TypeScript — no port needed. Sections B and C port to Node as below.

### Section B (Node): signature verification with `jose`

```typescript
import { jwtVerify, createRemoteJWKSet, errors } from 'jose';

const ALB_REGION = process.env.AWS_REGION!;
const EXPECTED_ISSUER = process.env.ALB_OIDC_EXPECTED_ISSUER!;
const EXPECTED_AUDIENCE = process.env.ALB_OIDC_EXPECTED_AUDIENCE!;

const JWKS = createRemoteJWKSet(
  new URL(`https://public-keys.auth.elb.${ALB_REGION}.amazonaws.com/`),
  { cooldownDuration: 24 * 60 * 60 * 1000 }   // 24h cache
);

export async function verifyAlbToken(token: string) {
  const { payload } = await jwtVerify(token, JWKS, {
    issuer: EXPECTED_ISSUER,
    audience: EXPECTED_AUDIENCE,
    algorithms: ['ES256'],   // AWS ALB uses ES256 — explicitly reject 'none' and HS256
  });
  return { email: payload.email as string, sub: payload.sub as string };
}
```

Startup validator (equivalent of Java's `AlbOidcPropertiesValidator`):

```typescript
if (!EXPECTED_ISSUER || !EXPECTED_AUDIENCE) {
  throw new Error(
    'FATAL: ALB_OIDC_EXPECTED_ISSUER and ALB_OIDC_EXPECTED_AUDIENCE must be set'
  );
}
```

### Section C (Node): Express middleware

```typescript
import { errors } from 'jose';
import { Request, Response, NextFunction } from 'express';

export async function albJwtMiddleware(req: Request, res: Response, next: NextFunction) {
  const token = req.header('x-amzn-oidc-data');
  if (!token) {
    res.status(401).json({ error: 'no_alb_oidc_data' });
    return;
  }
  try {
    const { email } = await verifyAlbToken(token);
    const user = await usersRepo.findByEmail(email);
    if (!user) {
      log.warn({ domain: domainOf(email) }, 'unknown email at domain — rejecting');
      res.status(401).json({ error: 'unknown_user' });
      return;
    }
    (req as any).user = user;
    next();
  } catch (e) {
    if (e instanceof errors.JWTInvalid || e instanceof errors.JWTExpired) {
      res.status(401).json({ error: 'invalid_token' });
      return;
    }
    next(e);
  }
}

app.use(albJwtMiddleware);
```

### Why `express-jwt` doesn't work directly

`express-jwt` expects a standard OIDC issuer with discovery (Auth0, Cognito, Okta). ALB JWTs are non-standard:
- The `kid` is a region-specific path component, not in standard JWKS metadata.
- AWS ALB signs with `ES256` (verify against the actual deployment).
- The verifier needs the regional public-keys endpoint, not OIDC discovery.

Write a thin custom middleware around `jose` directly, as shown.

### Differences from Java

- `jose` has built-in JWKS caching (`cooldownDuration`); no Caffeine setup.
- `errors.JWTInvalid` is a typed error class — clean `instanceof` discrimination.
- Express middleware is a function, not a `OncePerRequestFilter` class.
- TypeScript module augmentation (`declare module 'express-serve-static-core'`) replaces Java's typed principals.

## References

- AWS docs: ALB authentication —
  https://docs.aws.amazon.com/elasticloadbalancing/latest/application/listener-authenticate-users.html
