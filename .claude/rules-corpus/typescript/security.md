---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.mjs"
  - "**/*.cjs"
---
# Security Rules

> Extends [common/security.md](../common/security.md) w/ JS/TS content.

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deploy; no exceptions |
| **REQUIRED** | Follow unless overridden |
| **RECOMMENDED** | Best practice; team adjusts |

---

## CRITICAL: Security Review Every Change

Before task complete, verify:

- [ ] **No injection vulnerabilities** — SQL (parameterized queries), XSS (sanitized output), command injection (no `exec` with user input)
- [ ] **No sensitive data exposure** — no secrets in code or logs, no PII in logs, no tokens in responses
- [ ] **Authentication/authorization correct** — endpoints protected, permissions checked
- [ ] **Input validation** — all external input validated via Zod, size limits enforced
- [ ] **No insecure dependencies** — `npm audit` clean

---

## CRITICAL: No Hardcoded Secrets

```typescript
// NEVER
const apiKey = 'sk-proj-xxxxx'
const dbPassword = 'secret123'
const jwtSecret = 'my-secret-key'

// ALWAYS — environment variables
const apiKey = process.env.API_KEY
const dbUrl = process.env.DATABASE_URL

// Validate at startup
import { z } from 'zod'
const env = z.object({
  API_KEY: z.string().min(1),
  DATABASE_URL: z.string().url(),
  JWT_SECRET: z.string().min(32),
}).parse(process.env)
```

### CRITICAL: No Secrets in `.env` Committed to Git

```gitignore
# .gitignore
.env
.env.local
.env.production
```

Provide `.env.example` with placeholder values:

```bash
# .env.example
API_KEY=your-api-key-here
DATABASE_URL=postgresql://localhost:5432/myapp
JWT_SECRET=generate-a-random-32-char-string
```

---

## CRITICAL: No Sensitive Data in Logs

```typescript
// NEVER
logger.info(`Login with password: ${password}`)
logger.debug(`Token: ${authToken}`)
logger.info(`User: ${JSON.stringify(userWithPII)}`)

// ALWAYS
logger.info({ userId }, 'Login attempt')
logger.debug('Authentication successful')
```

---

## REQUIRED: Parameterized Queries

```typescript
// NEVER — SQL injection
const query = `SELECT * FROM users WHERE id = '${userId}'`
await db.query(`SELECT * FROM orders WHERE status = '${status}'`)

// ALWAYS — parameterized
await db.query('SELECT * FROM users WHERE id = $1', [userId])

// With Prisma — safe by default
await prisma.user.findUnique({ where: { id: userId } })

// With Drizzle — safe by default
await db.select().from(users).where(eq(users.id, userId))

// DANGER — raw queries still need parameterization
await prisma.$queryRaw`SELECT * FROM users WHERE id = ${userId}`  // GOOD — tagged template
await prisma.$queryRawUnsafe(`SELECT * FROM users WHERE id = '${userId}'`)  // BAD
```

---

## REQUIRED: XSS Prevention

### Server-Side Rendering

```typescript
// NEVER — unescaped user input in HTML
res.send(`<h1>${userInput}</h1>`)

// ALWAYS — escape or use a template engine that auto-escapes
import escape from 'escape-html'
res.send(`<h1>${escape(userInput)}</h1>`)
```

### React (JSX) — Safe by Default

```tsx
// SAFE — React escapes by default
<p>{userInput}</p>

// DANGEROUS — bypasses escaping
<div dangerouslySetInnerHTML={{ __html: userInput }} />  // NEVER with user input
```

### Content Security Policy

```typescript
// Express — use helmet
import helmet from 'helmet'
app.use(helmet())

// Or manually
app.use((req, res, next) => {
  res.setHeader('Content-Security-Policy', "default-src 'self'")
  res.setHeader('X-Content-Type-Options', 'nosniff')
  res.setHeader('X-Frame-Options', 'DENY')
  next()
})
```

---

## REQUIRED: CSRF Protection

Cookie-based auth (session cookies):

```typescript
// Express
import csrf from 'csurf'
app.use(csrf({ cookie: true }))

// Or use SameSite cookies
res.cookie('session', token, {
  httpOnly: true,
  secure: true,
  sameSite: 'strict',
  maxAge: 3600000,
})
```

**Note:** Bearer token auth = CSRF-safe.

---

## REQUIRED: Rate Limiting

```typescript
// Express
import rateLimit from 'express-rate-limit'

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,  // 15 minutes
  max: 100,                    // limit per window
  standardHeaders: true,
  legacyHeaders: false,
})

app.use('/api/', limiter)

// Stricter for auth endpoints
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
})

app.use('/api/v1/auth/login', authLimiter)
```

---

## REQUIRED: Input Validation

Validate all external input at boundaries:

```typescript
import { z } from 'zod'

// Size limits enforced
const CreateOrderSchema = z.object({
  email: z.string().email().max(255),
  description: z.string().min(1).max(1000),
  items: z.array(z.object({
    productId: z.string().uuid(),
    quantity: z.number().int().positive().max(10000),
  })).min(1).max(100),
})

// File uploads — validate size and type
const MAX_FILE_SIZE = 5 * 1024 * 1024  // 5MB
const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'application/pdf']
```

---

## REQUIRED: No Command Injection

```typescript
// NEVER — user input in shell commands
import { exec } from 'child_process'
exec(`ls ${userInput}`)             // Command injection
exec(`convert ${filename} out.png`)  // Path traversal + injection

// ALWAYS — use execFile with arguments array
import { execFile } from 'child_process'
execFile('ls', [userInput])
execFile('convert', [filename, 'out.png'])

// Or avoid shell entirely
import { readdir } from 'fs/promises'
const files = await readdir(validatedPath)
```

---

## REQUIRED: Path Traversal Prevention

```typescript
import path from 'path'

// NEVER — user input directly in file path
const filePath = `./uploads/${req.params.filename}`
fs.readFile(filePath)

// ALWAYS — resolve and validate
const UPLOADS_DIR = path.resolve('./uploads')
const filePath = path.resolve(UPLOADS_DIR, req.params.filename)

if (!filePath.startsWith(UPLOADS_DIR)) {
  throw new ForbiddenError('Path traversal detected')
}

await fs.readFile(filePath)
```

---

## REQUIRED: Dependency Security

```bash
# Check for vulnerabilities
npm audit

# In CI — fail on high/critical
npm audit --audit-level=high

# Keep dependencies updated
npx npm-check-updates
```

---

## RECOMMENDED: Security Headers

Use `helmet` (Express) or set manually:

```typescript
// Essential headers
{
  'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'X-XSS-Protection': '0',  // Deprecated, but set to 0
  'Content-Security-Policy': "default-src 'self'",
  'Referrer-Policy': 'strict-origin-when-cross-origin',
}
```

---

## Quick Reference

| Rule | Priority |
|------|----------|
| Security review every change | CRITICAL |
| No hardcoded secrets | CRITICAL |
| No secrets in committed .env | CRITICAL |
| No sensitive data in logs | CRITICAL |
| Parameterized queries | REQUIRED |
| XSS prevention | REQUIRED |
| CSRF protection (cookie auth) | REQUIRED |
| Rate limiting | REQUIRED |
| Input validation (Zod) | REQUIRED |
| No command injection (execFile, not exec) | REQUIRED |
| Path traversal prevention | REQUIRED |
| Dependency security (npm audit) | REQUIRED |
| Security headers (helmet) | RECOMMENDED |
