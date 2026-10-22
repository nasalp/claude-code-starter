---
name: spa-e2e-redux-persist-auth
description: Inject Playwright authentication into Redux Persist SPAs without hitting the rate limiter — pre-login once in global-setup, double-stringify into persist:root, and use addInitScript before the SPA...
origin: ECC
triggers: addInitScript, persist:root, redux-persist, persist version, auth-cache.json, authLimiter, Playwright SPA login, loginViaAPI, loginViaUI, auth cache miss, SPA rate limit, vite e2e auth
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
---
# SPA E2E Authentication for Redux Persist

Logging into a Redux-Persist SPA from Playwright is full of small traps. Browser tests need a logged-in state without driving the UI through a brittle login form, but Redux Persist serializes state with double JSON encoding under a versioned `_persist` key, and the dashboard's auth rate limiter (10 attempts per 15 minutes per IP) will lock you out if every test re-authenticates. This skill is the working pattern in `e2e/helpers/` that handles all of it.

## When to use

- E2E tests against an SPA that uses `redux-persist` (look for `persist:root` in localStorage).
- A backend with an authentication rate limiter that you cannot disable in test mode.
- Multi-worker Playwright runs where every worker needs an authenticated session.
- Auth tokens that need to be available in the page before the SPA's first render.

## When NOT to use

- Tests that explicitly cover the login flow itself — those should drive the UI via `loginViaUI`.
- Backends with HttpOnly cookie auth and no client-side token (use `context.addCookies()` instead).
- Apps that hydrate auth from a server-rendered HTML payload (the trick relies on localStorage being read at boot).

## The pattern

Three pieces: pre-login once in global-setup, cache tokens to disk, inject via `addInitScript`.

### 1. Pre-login once in global-setup

`authLimiter` allows 10 attempts per 15 minutes per IP. With 4 Playwright workers and 3 tests each, you'll exhaust it on a cold run. The fix is to authenticate every test user once, in `e2e/global-setup.ts`, before any worker starts:

```typescript
const users = [
  { email: 'e2e-admin@example.test', password: 'E2eAdminPass!123' },
  { email: 'e2e-locmanager@example.test', password: 'E2eLocMgr!123' },
];
const authCache: Record<string, any> = {};
for (const user of users) {
  const res = await fetch(`http://localhost:${PORTS.dashboardV2}/api/v2/auth/`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: user.email, password: user.password }),
  });
  if (res.ok) {
    const body = await res.json();
    const data = (body as any).data || body;
    authCache[user.email] = { token: data.token, user: data.user, permissions: data.permissions || {} };
  }
}
writeAuthCache(authCache);
```

The loop is sequential, not concurrent — concurrent logins from the same IP burn the rate limiter just as fast as a fan-out from workers would.

### 2. Cache to disk, workers read-only

`e2e/helpers/auth-cache.ts` writes `e2e/.auth-cache.json` under `.gitignore`. Workers read but never write:

```typescript
export function readAuthCache(): AuthCache {
  try { return JSON.parse(fs.readFileSync(AUTH_CACHE_FILE, 'utf-8')); }
  catch { return {}; }
}
```

Global-setup deletes the file at the start of every run (`deleteAuthCache()`) so a stale token from a previous run doesn't leak in.

### 3. Inject with `addInitScript` before the SPA boots

The Redux Persist storage shape requires care. The reducer state is JSON-stringified, then the entire `persist:root` object is JSON-stringified again. A version-mismatch in `_persist.version` makes Redux Persist discard the rehydrated state and revert to defaults — losing your auth.

```typescript
const authState = {
  user: { token, user: user || {}, permissions: permissions || {} },
  company: null,
  hasSubscribedToPlan: true,
  hasCompletedOnboarding: true,
};
const persistState = {
  auth: JSON.stringify(authState),                              // inner stringify
  _persist: JSON.stringify({ version: -1, rehydrated: true }), // version must match the app
};
const persistJson = JSON.stringify(persistState);              // outer stringify

await page.addInitScript((json: string) => {
  localStorage.setItem('persist:root', json);
}, persistJson);

await page.goto(`${baseUrl}/`, { waitUntil: 'domcontentloaded' });
```

Crucially, `addInitScript` runs **before any page JavaScript loads**, so the SPA's Redux Persist rehydrator sees the injected state during initial bootstrap and doesn't overwrite it with the default unauthenticated state. Calling `page.evaluate(...)` after navigation is too late — the SPA has already rendered the login screen and the Persist gate has flipped to "rehydrated".

### 4. Verify the SPA didn't redirect to /auth/login

The injected state can still be rejected (wrong version, wrong shape, expired token). Verify:

```typescript
try {
  await page.waitForURL((url) => !url.pathname.includes('/auth/login'),
    { timeout: 15_000, waitUntil: 'domcontentloaded' });
} catch {
  // Retry once — sometimes Vite's first compile makes the first request slow
  await page.goto(`${baseUrl}/`, { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle');
}
```

If the SPA redirects, the most common cause is a `_persist.version` mismatch with the app's current persist config. Check the app's `persistReducer` config; the version must be identical. The codebase uses `version: -1`, which is `redux-persist`'s pre-migration default.

## Common gotchas / variants

- The dashboard returns `{ data: { token, user, permissions } }` on some routes and the bare object on others — handle both: `const data = (body as any).data || body`.
- The frontend port (5173) and API port (4000) differ. The auth API call goes to 4000; the page goto goes to 5173. Don't accidentally `addInitScript` on the API origin.
- Multi-tab tests: `addInitScript` is per-context, not per-page. Open a new context per role to avoid token cross-contamination.
- If you also store auth in `sessionStorage`, replicate the injection there. Redux Persist supports a session store; check the app's storage adapter.
- Don't write the auth cache from inside a worker. If a test needs a fresh token (e.g., expiry test), call the login API from that test directly — don't mutate the shared cache.
- `auth-cache.json` MUST be gitignored. The cache holds real JWT tokens for test users; even though they're test-only, dev keys can leak into bug reports.

## Verification

- `cat e2e/.auth-cache.json | jq 'keys'` after `npx playwright test --project=setup` — must list every test user.
- A throwaway test: `await loginViaAPI(page, 'e2e-admin@example.test', '...')` then `expect(page.url()).not.toContain('/auth/login')`.
- Inspect the page after `addInitScript`: `await page.evaluate(() => JSON.parse(localStorage.getItem('persist:root') || '{}'))` — the returned object must have an `auth` field whose value is itself a JSON string.
- Try with a deliberately wrong `_persist.version` — the test should fail cleanly because the SPA redirects to login. That confirms the version-matching is what makes the trick work.
