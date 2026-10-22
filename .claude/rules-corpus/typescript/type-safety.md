---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.mjs"
  - "**/*.cjs"
---
# Type Safety Rules

Non-null by default, strict everywhere. TypeScript strict mode or JSDoc + checkJs.

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deployment, no exceptions |
| **REQUIRED** | Must follow unless explicitly overridden |
| **RECOMMENDED** | Best practice, team can adjust |

---

## CRITICAL: Strict Mode Always On

### TypeScript Projects

```jsonc
// tsconfig.json
{
  "compilerOptions": {
    "strict": true,                    // Enables ALL strict checks
    "noUncheckedIndexedAccess": true,  // array[0] is T | undefined
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "exactOptionalPropertyTypes": true,
    "noPropertyAccessFromIndexSignature": true
  }
}
```

### Plain JavaScript Projects

Use JSDoc + TypeScript checker:

```jsonc
// jsconfig.json or tsconfig.json
{
  "compilerOptions": {
    "checkJs": true,
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "allowJs": true,
    "noEmit": true
  },
  "include": ["src/**/*.js"]
}
```

```javascript
// JSDoc type annotations in .js files

/** @param {string} name */
/** @returns {import('./types').User} */
function createUser(name) {
  return { name, createdAt: new Date() }
}

/** @type {Map<string, import('./types').Session>} */
const sessions = new Map()
```

---

## CRITICAL: No `any`

`any` disables the type system. It is a bug waiting to happen.

```typescript
// NEVER
function process(data: any) { }
const result: any = fetchData()
// @ts-ignore

// ALWAYS — use specific types
function process(data: UserRequest) { }
const result: unknown = fetchData()  // then narrow

// If you truly don't know the shape, use unknown + narrowing
function handle(input: unknown): string {
  if (typeof input === 'string') return input
  if (isUserRequest(input)) return input.name
  throw new Error('Unexpected input type')
}
```

### ESLint Enforcement

```jsonc
{
  "rules": {
    "@typescript-eslint/no-explicit-any": "error",
    "@typescript-eslint/no-unsafe-assignment": "error",
    "@typescript-eslint/no-unsafe-member-access": "error",
    "@typescript-eslint/no-unsafe-call": "error",
    "@typescript-eslint/no-unsafe-return": "error"
  }
}
```

For plain JS with JSDoc:

```javascript
// NEVER
/** @param {*} data */
function process(data) { }

// ALWAYS
/** @param {import('./types').UserRequest} data */
function process(data) { }
```

---

## REQUIRED: Validate at Boundaries

Internal code trusts types. Boundaries (user input, API responses, env vars) MUST validate at runtime.

### Zod for Runtime Validation

```typescript
import { z } from 'zod'

// Define schema at the boundary
const CreateOrderSchema = z.object({
  email: z.string().email(),
  amount: z.number().positive(),
  description: z.string().min(1).max(100),
})

type CreateOrderRequest = z.infer<typeof CreateOrderSchema>

// In route handler — parse once, trust everywhere after
const body = CreateOrderSchema.parse(req.body)
// body is now fully typed and validated
```

### Environment Variables

```typescript
const EnvSchema = z.object({
  DATABASE_URL: z.string().url(),
  API_KEY: z.string().min(1),
  PORT: z.coerce.number().int().positive().default(3000),
  NODE_ENV: z.enum(['development', 'production', 'test']),
})

// Validate at startup — fail fast
const env = EnvSchema.parse(process.env)
```

For plain JS:

```javascript
// @ts-check
const { z } = require('zod')

const EnvSchema = z.object({
  DATABASE_URL: z.string().url(),
  PORT: z.coerce.number().default(3000),
})

/** @type {z.infer<typeof EnvSchema>} */
const env = EnvSchema.parse(process.env)
```

---

## REQUIRED: Prefer `unknown` Over `any` for Catch Blocks

```typescript
// NEVER
try { } catch (error: any) {
  console.log(error.message)  // unsafe
}

// ALWAYS
try { } catch (error: unknown) {
  if (error instanceof AppError) {
    console.log(error.message)
  }
  throw error
}

// Or use a type guard
function isError(value: unknown): value is Error {
  return value instanceof Error
}
```

---

## REQUIRED: Use Branded Types for Domain Identifiers

Don't pass raw strings where a specific ID is expected:

```typescript
// NEVER — easy to swap userId and orderId by accident
function getOrder(userId: string, orderId: string) { }

// ALWAYS — branded types prevent mixups
type UserId = string & { readonly __brand: 'UserId' }
type OrderId = string & { readonly __brand: 'OrderId' }

function userId(id: string): UserId { return id as UserId }
function orderId(id: string): OrderId { return id as OrderId }

function getOrder(userId: UserId, orderId: OrderId) { }

// Compile error: can't pass OrderId where UserId expected
getOrder(orderId('abc'), userId('def'))  // ERROR
```

For plain JS, use JSDoc + type imports:

```javascript
/**
 * @param {import('./types').UserId} userId
 * @param {import('./types').OrderId} orderId
 */
function getOrder(userId, orderId) { }
```

---

## REQUIRED: Discriminated Unions for State

```typescript
// NEVER — optional fields hide illegal states
type Order = {
  status: string
  shippedAt?: Date
  cancelReason?: string
}

// ALWAYS — discriminated union makes illegal states unrepresentable
type Order =
  | { status: 'pending'; createdAt: Date }
  | { status: 'shipped'; createdAt: Date; shippedAt: Date }
  | { status: 'cancelled'; createdAt: Date; cancelReason: string }

// Exhaustive switch — compiler catches missing cases
function handle(order: Order) {
  switch (order.status) {
    case 'pending': return processPending(order)
    case 'shipped': return processShipped(order)
    case 'cancelled': return processCancelled(order)
    default: {
      const _exhaustive: never = order
      throw new Error(`Unhandled status: ${_exhaustive}`)
    }
  }
}
```

---

## REQUIRED: Static Analysis Pipeline

### TypeScript Projects

3 tools, all fail on violation:

| # | Tool | Purpose |
|---|------|---------|
| 1 | **TypeScript compiler** (`tsc --noEmit`) | Type checking |
| 2 | **ESLint** (with `@typescript-eslint`) | Bug detection + style |
| 3 | **Prettier** or **Biome** | Formatting |

```bash
# CI pipeline
tsc --noEmit                  # Type check
eslint . --max-warnings 0     # Lint (zero warnings policy)
prettier --check .            # Format check
```

### Plain JavaScript Projects

```bash
# CI pipeline
tsc --noEmit --checkJs        # Type check JS via JSDoc
eslint . --max-warnings 0     # Lint
prettier --check .            # Format
```

### ESLint Minimum Config

```javascript
// eslint.config.js
import tseslint from 'typescript-eslint'

export default tseslint.config(
  tseslint.configs.strictTypeChecked,
  {
    rules: {
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      '@typescript-eslint/no-floating-promises': 'error',
      '@typescript-eslint/no-misused-promises': 'error',
      '@typescript-eslint/prefer-nullish-coalescing': 'error',
      '@typescript-eslint/prefer-optional-chain': 'error',
      'no-console': ['error', { allow: ['warn', 'error'] }],
    },
  },
)
```

---

## RECOMMENDED: `satisfies` Over Type Assertions

```typescript
// NEVER — type assertion hides errors
const config = {
  port: 3000,
  host: 'localhost',
} as Config

// ALWAYS — satisfies validates AND preserves literal types
const config = {
  port: 3000,
  host: 'localhost',
} satisfies Config
```

---

## Quick Reference

| Rule | Priority |
|------|----------|
| `strict: true` in all projects | CRITICAL |
| `checkJs: true` for plain JS projects | CRITICAL |
| No `any` anywhere | CRITICAL |
| Validate at boundaries (Zod) | REQUIRED |
| `unknown` in catch blocks | REQUIRED |
| Branded types for domain IDs | REQUIRED |
| Discriminated unions for state | REQUIRED |
| 3-tool static analysis pipeline | REQUIRED |
| `satisfies` over type assertions | RECOMMENDED |

> Rationale (Why): `docs/rule-rationale/typescript__type-safety.md`
