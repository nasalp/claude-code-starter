---
name: xff-trusted-proxy-resolver
description: Consume X-Forwarded-For safely behind ALB/CloudFront/nginx without enabling rate-limit-key spoofing or per-IP audit log forgery. Trusted-proxy CIDR list, fail-closed default.
origin: ECC
triggers: X-Forwarded-For, XFF, RateLimitFilter, getRemoteAddr, IpAddressMatcher, trusted proxies, ALB OIDC, rate limit bypass, per-IP rate limit, client IP, reverse proxy
---
# X-Forwarded-For Trusted Proxy Resolver

`X-Forwarded-For` is a hop-by-hop hint set by the **immediate HTTP peer**. Behind a load balancer the peer is the load balancer and the header is authoritative. From any other peer — direct internet hits when security groups misbehave, a misconfigured Layer-4 proxy, sidecars, local requests — the header is **attacker-controlled**.

Treating XFF as authoritative without checking the peer is one of the oldest perimeter mistakes. It enables rate-limit bypass, per-IP audit log forgery, geo-IP spoofing for compliance lookups, and IP allowlist bypass for "internal-only" endpoints.

## When to use

- You read `X-Forwarded-For` (or `X-Real-IP`, `Forwarded`, `True-Client-IP`) anywhere — rate limiting, audit logging, geo-IP, IP-based feature flags, fraud signals.
- Your app sits behind a load balancer / CDN / reverse proxy chain.
- You are reviewing a `getRemoteAddr()` callsite that the team has "improved" to read XFF instead.

## When NOT to use

- The application is direct-internet-facing with no proxy in front. Use `request.getRemoteAddr()` only and ignore XFF entirely.
- You are bound to the servlet container's reverse-proxy support (`server.forward-headers-strategy=NATIVE` in Spring Boot, Tomcat's `RemoteIpValve`). The container already implements this pattern; do not re-implement on top of it. Do verify the trust list there.

## The pattern

Trust XFF only when the immediate peer is in a **configured trusted-proxy CIDR set**. Without configuration, fall back to the peer address — **fail-closed against spoof**.

```java
@ConfigurationProperties("app.shared.rate-limit")
record RateLimitProperties(List<String> trustedProxies) {
    RateLimitProperties {
        trustedProxies = trustedProxies == null ? List.of() : List.copyOf(trustedProxies);
    }
}

class RateLimitFilter extends OncePerRequestFilter {

    private final List<IpAddressMatcher> trustedProxyMatchers;

    RateLimitFilter(BucketResolver bucketResolver, @Nullable List<String> trustedProxyCidrs) {
        this.bucketResolver = bucketResolver;
        this.trustedProxyMatchers = (trustedProxyCidrs == null) ? List.of()
                : trustedProxyCidrs.stream().map(IpAddressMatcher::new).toList();
    }

    String resolveClientIp(HttpServletRequest request) {
        String peer = request.getRemoteAddr();
        if (!isTrustedPeer(peer, request)) {
            return peer;                          // fail-closed
        }
        @Nullable String forwarded = request.getHeader("X-Forwarded-For");
        if (forwarded != null && !forwarded.isBlank()) {
            int comma = forwarded.indexOf(',');
            return (comma > 0) ? forwarded.substring(0, comma).trim()
                               : forwarded.trim();
        }
        return peer;
    }

    private boolean isTrustedPeer(@Nullable String peer, HttpServletRequest request) {
        if (peer == null || trustedProxyMatchers.isEmpty()) {
            return false;
        }
        for (IpAddressMatcher matcher : trustedProxyMatchers) {
            if (matcher.matches(request)) return true;
        }
        return false;
    }
}
```

Production behind AWS ALB sets the VPC ranges. Dev / test leave it empty:

```yaml
app:
  shared:
    rate-limit:
      trusted-proxies:
        - 10.0.0.0/8
        - 172.16.0.0/12
```

`IpAddressMatcher` ships with Spring Security; it accepts both IPv4 and IPv6 CIDR notation and inspects `request.getRemoteAddr()` against the mask.

## The rightmost-trusted walk

A single trusted hop is the common case. Multi-hop chains (ALB to nginx to app) need the **rightmost-trusted walk-up** to find the real client:

1. Start at the leftmost XFF entry — the original client's claim.
2. Walk **right** through the XFF list. Each entry is the IP that the next hop saw as its peer.
3. Stop at the first entry that is **not** in the trusted-proxy set. That IP is the real client.

In other words: trust addresses while they remain inside the trusted chain; the first untrusted address from the right is the client. The leftmost-only short-cut works for a single trusted hop because in that case leftmost == rightmost-untrusted.

```java
String walkUp(List<String> xffChain, List<IpAddressMatcher> trusted, String fallback) {
    for (int i = xffChain.size() - 1; i >= 0; i--) {
        String hop = xffChain.get(i).trim();
        if (!isInTrusted(hop, trusted)) return hop;   // first untrusted
    }
    return fallback;                                  // entire chain trusted
}
```

## Common gotchas / variants

- **`request.getHeader("X-Forwarded-For")` returns the full comma-list, not just the leftmost.** Splitting matters; a header like `1.2.3.4, 10.0.0.5` from a trusted ALB peer means "client claims 1.2.3.4, ALB observed it at 10.0.0.5". Pick the entry per the walk-up above.
- **Header case insensitivity.** Servlet API normalizes; raw nginx logs do not. Compare lower-case.
- **IPv6 `::ffff:1.2.3.4` mapped form.** `IpAddressMatcher` handles it, but custom string equality on peer addresses will miss the match.
- **CDN-specific headers.** Cloudflare uses `CF-Connecting-IP`, AWS CloudFront uses `CloudFront-Viewer-Address`, Fastly uses `Fastly-Client-IP`. Same trust-the-peer rule applies — trust the CDN-injected header only when the peer is the CDN egress.
- **`X-Real-IP` (single value).** Same vulnerability surface as XFF. Same fix — gate on peer trust.
- **`Forwarded:` (RFC 7239).** Structured header, same trust model. Parse `for=` parameters with the same walk-up.
- **Tomcat's `RemoteIpValve` / Spring Boot's `server.forward-headers-strategy`.** These already implement the pattern at the container level. When the valve is active, `request.getRemoteAddr()` returns the resolved client IP; do not re-read XFF in application code.
- **Local development.** Empty trusted-proxy list is correct. Direct 127.0.0.1 hits keep `getRemoteAddr()` as the key.
- **Trusted-proxy CIDR drift.** ALB IPs change; AWS publishes an `ip-ranges.json` feed. Either pin the VPC subnet (stable) or refresh the CIDR list from the feed at deploy time.

## Verification

Three regression tests pin the contract:

```java
@Test
void should_ignore_x_forwarded_for_from_untrusted_peer() {
    // peer 203.0.113.99 is NOT in trustedProxies — XFF is ignored
    // expect rate-limit key = 203.0.113.99
}

@Test
void should_honor_x_forwarded_for_from_trusted_peer() {
    // peer 10.0.0.5 IS in 10.0.0.0/8 — XFF leftmost wins
    // expect rate-limit key = 1.2.3.4
}

@Test
void should_reject_spoofed_x_forwarded_for_attempt_to_bypass_rate_limit() {
    // CAPACITY+1 requests from one peer with rotating XFF values
    // request CAPACITY+1 still returns 429 because the peer is the key
}
```

The third test is the load-bearing one: an attacker rotating the XFF header per request must NOT get a fresh bucket. If that test goes green when XFF is unconditionally honored, the rate limit is bypassable.

## Node.js / TypeScript equivalent

### Express: `app.set('trust proxy', ...)`

Express has a built-in trust-proxy mechanism. Valid arguments:

- `false` (default) — never trust XFF.
- A specific IP/CIDR string or array — trust only those peers.
- An integer N — trust the rightmost N hops blindly. **Avoid this.**
- `'loopback'`, `'linklocal'`, `'uniquelocal'` — convenience aliases.
- `true` — trust all proxies. **NEVER USE THIS** in production.

```typescript
import express from 'express';

const app = express();

// Production behind AWS ALB: trust the VPC ranges only.
app.set('trust proxy', ['10.0.0.0/8', '172.16.0.0/12']);

// Local dev: leave it false (the default).

app.get('/api/whoami', (req, res) => {
  // req.ip respects the trust list. Untrusted peer => req.ip === socket.remoteAddress.
  // Trusted peer + valid XFF => req.ip === leftmost trusted-walk-up entry.
  res.json({ clientIp: req.ip, ips: req.ips });
});
```

### Rate-limit key derivation

```typescript
import rateLimit from 'express-rate-limit';

const limiter = rateLimit({
  windowMs: 60 * 1000,
  max: 100,
  keyGenerator: (req) => req.ip,   // safe iff `trust proxy` is configured
});
app.use(limiter);
```

### Defending against `trust proxy: true`

Add a startup check that refuses to boot with `app.get('trust proxy') === true`:

```typescript
if (app.get('trust proxy') === true) {
  throw new Error('FATAL: app.set("trust proxy", true) accepts spoofed XFF — use a CIDR list');
}
```

### Manual walk-up with `ipaddr.js`

For finer control (or when not using Express):

```typescript
import ipaddr from 'ipaddr.js';

const trusted = ['10.0.0.0/8', '172.16.0.0/12'].map(c => ipaddr.parseCIDR(c));

function isInTrusted(ip: string): boolean {
  const parsed = ipaddr.parse(ip);
  return trusted.some(([addr, prefix]) =>
    parsed.kind() === addr.kind() && parsed.match(addr, prefix)
  );
}
```

### Differences from Java

- `req.ip` does the trust-walk for you when `trust proxy` is set; no custom filter needed.
- `app.set('trust proxy', true)` is a footgun — never appropriate for prod-facing apps.
- No `IpAddressMatcher` analogue in stdlib; use `ipaddr.js` for CIDR matching.

## References

- Implementation:
- Spring Security `IpAddressMatcher` — `org.springframework.security.web.util.matcher.IpAddressMatcher`
- Tomcat `RemoteIpValve`, `server.forward-headers-strategy=NATIVE` (Spring Boot)
- RFC 7239 — `Forwarded` header
- AWS `ip-ranges.json` — published egress CIDR feed for ALB/CloudFront
