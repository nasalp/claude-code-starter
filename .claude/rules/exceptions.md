# Rule Exceptions

When and how rules bypassed.

---

## Exception Types

### 1. User Override

User explicitly requests skip rule for current task.

**Trigger phrases:**
- "Skip the spec for now"
- "Don't write tests for this"
- "Just implement it quickly"
- "Prototype this without tests"

**Agent behavior:**
```
User: "Add a status field to User. Skip the spec, I'll document it later."

Agent: "Understood. Implementing without spec as requested.

Note: Remember to add spec at `spec/features/user/status-field.md` before production."
```

**Rules:**
- Override applies **only to current task**
- Agent **MUST note** what was skipped
- Agent **MUST NOT suggest** skipping — only honor explicit requests
- Agent **SHOULD recommend** completing skipped work later

### 2. Legacy Code

Existing code doesn't follow current standards.

**Allowed:**
- Leave untouched legacy code as-is
- Only update code you're directly modifying
- Don't add tests for untouched code

**Required:**
- New code you write must follow current rules
- Document significant deviations with TODO comments
- Create tech debt ticket for major issues

See [legacy-code.md](legacy-code.md) for details.

### 3. External Constraints

Third-party libraries or APIs force deviation.

**Examples:** library requires public classes; external API uses different naming convention; framework limitation prevents best practice.

**Required:**
- Document the constraint
- Isolate affected code (adapter pattern)
- Don't let constraint leak into domain code

```java
// External API requires this format — isolate in adapter
class ExternalPaymentAdapter {
    // Public because framework requires it
    // See: https://github.com/payment-lib/issues/123
    public PaymentResult process(PaymentRequest request) { }
}
```

### 4. Time-Critical Hotfix

Production down, need immediate fix.

**Allowed:**
- Skip spec (document later)
- Minimal testing (add comprehensive tests after)
- Skip code review (review after deployment)

**Required:**
- Fix MUST be minimal
- Create follow-up ticket immediately
- Complete skipped steps within 48 hours

```
// HOTFIX: PROD-911 — Production orders failing
// TODO: Add spec and tests — ticket PROJ-789
// Deadline: 2024-01-17
```

---

## Exception Process

### Step 1: Recognize the Exception

| Situation | Exception Type |
|-----------|----------------|
| User says "skip X" | User Override |
| Existing code violates rule | Legacy Code |
| Library forces deviation | External Constraint |
| Production outage | Time-Critical Hotfix |

### Step 2: Document

Always document exceptions:

```java
// EXCEPTION: <type>
// Rule violated: <which rule>
// Reason: <why exception applies>
// Follow-up: <what needs to happen later>
// Ticket: <tracking ticket if applicable>
```

### Step 3: Minimize Scope

Exception applies to **minimum scope necessary**:
- One file, not whole module
- One method, not whole class
- One task, not all future tasks

### Step 4: Track Follow-Up

For anything deferred: create ticket/TODO, set deadline, assign owner.

---

## What's NEVER Excepted

Some rules cannot bypass regardless of circumstance:

| Rule | Why No Exceptions |
|------|-------------------|
| No sensitive data in logs | Security/compliance |
| Bounded caches/queues | System stability |
| No hardcoded secrets | Security |
| Tests must actually run | Quality assurance |

Even in hotfixes, these rules apply.

---

## Agent Decision Tree

```
Is user explicitly overriding?
├── YES → Honor override, document skip, recommend follow-up
└── NO → Is this legacy code you're not modifying?
         ├── YES → Leave as-is, no changes needed
         └── NO → Is there an external constraint?
                  ├── YES → Document, isolate, proceed
                  └── NO → Is this a production emergency?
                           ├── YES → Minimal fix, create follow-up ticket
                           └── NO → Follow the rules
```

---

## Example Responses

### User Override
```
User: "Add a quick endpoint for health checks. No need for spec."

Agent: "Adding health endpoint without spec as requested.

Created: `src/.../HealthController.java`

Note: Consider adding `spec/features/infrastructure/health-check.md`
if this becomes a documented API contract."
```

### Legacy Code
```
User: "Fix the bug in LegacyOrderService"

Agent: "Fixed the bug in `findOrder()` method.

Note: This class uses JUnit5 assertions (legacy). I added the fix with
a characterization test using existing patterns. New code follows
current AssertJ standards."
```

### External Constraint
```
Agent: "Implemented payment integration.

Note: PaymentAdapter is public (required by payment-sdk library).
See https://github.com/payment-sdk/issues/456.
Domain code remains package-private — adapter is isolated."
```
