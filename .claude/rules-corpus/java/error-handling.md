---
paths:
  - "**/*.java"
---

# Error Handling Rules

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deployment, no exceptions |
| **REQUIRED** | Must follow unless explicitly overridden |
| **RECOMMENDED** | Best practice, team can adjust |

---

## Exception Hierarchy

### REQUIRED: Domain Exceptions

Domain-specific exceptions — not generic:

```java
// ✅ Good — specific domain exceptions
class OrderNotFoundException extends RuntimeException {
    private final OrderId orderId;

    OrderNotFoundException(OrderId orderId) {
        super("Order not found: " + orderId);
        this.orderId = orderId;
    }

    public OrderId getOrderId() { return orderId; }
}

class OrderAlreadyCancelledException extends RuntimeException { }
class InsufficientInventoryException extends RuntimeException { }

// ❌ Bad — generic
throw new RuntimeException("Order not found");
throw new Exception("Something went wrong");
```

### RECOMMENDED: Exception Hierarchy

```
BusinessException (abstract)
├── NotFoundException
│   ├── OrderNotFoundException
│   └── UserNotFoundException
├── ValidationException
│   ├── InvalidOrderStateException
│   └── InvalidAmountException
└── ConflictException
    ├── OrderAlreadyCancelledException
    └── DuplicateEmailException
```

---

## HTTP Error Responses

### REQUIRED: Consistent Error Format

```java
record ErrorResponse(
    String code,           // Machine-readable: "ORDER_NOT_FOUND"
    String message,        // Human-readable: "Order not found"
    String traceId,        // For debugging: correlation ID
    Instant timestamp,
    Map<String, String> details  // Optional field-level errors
) {}
```

### REQUIRED: Global Exception Handler

```java
@RestControllerAdvice
class GlobalExceptionHandler {

    @ExceptionHandler(NotFoundException.class)
    ResponseEntity<ErrorResponse> handleNotFound(NotFoundException ex, HttpServletRequest request) {
        return ResponseEntity
            .status(HttpStatus.NOT_FOUND)
            .body(new ErrorResponse(
                ex.getErrorCode(),
                ex.getMessage(),
                getTraceId(),
                Instant.now(),
                null
            ));
    }

    @ExceptionHandler(ValidationException.class)
    ResponseEntity<ErrorResponse> handleValidation(ValidationException ex) {
        return ResponseEntity
            .status(HttpStatus.BAD_REQUEST)
            .body(new ErrorResponse(
                "VALIDATION_ERROR",
                ex.getMessage(),
                getTraceId(),
                Instant.now(),
                ex.getFieldErrors()
            ));
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<ErrorResponse> handleUnexpected(Exception ex) {
        log.error("Unexpected error", ex);  // Log full stack trace
        return ResponseEntity
            .status(HttpStatus.INTERNAL_SERVER_ERROR)
            .body(new ErrorResponse(
                "INTERNAL_ERROR",
                "An unexpected error occurred",  // Don't expose details
                getTraceId(),
                Instant.now(),
                null
            ));
    }
}
```

### REQUIRED: HTTP Status Mapping

| Exception Type | HTTP Status | When |
|----------------|-------------|------|
| `NotFoundException` | 404 | Resource doesn't exist |
| `ValidationException` | 400 | Invalid input |
| `ConflictException` | 409 | State conflict (already exists, already cancelled) |
| `UnauthorizedException` | 401 | Not authenticated |
| `ForbiddenException` | 403 | Not authorized |
| `Unexpected` | 500 | Unhandled errors |

---

## Validation Errors

### REQUIRED: Field-Level Details

```java
// Response for validation errors
{
    "code": "VALIDATION_ERROR",
    "message": "Invalid request",
    "traceId": "abc-123",
    "timestamp": "2024-01-15T10:30:00Z",
    "details": {
        "email": "Invalid email format",
        "amount": "Must be greater than 0"
    }
}
```

### REQUIRED: Use Bean Validation

```java
record CreateOrderRequest(
    @NotNull @Email String email,
    @NotNull @Positive BigDecimal amount,
    @NotBlank @Size(max = 100) String description
) {}
```

---

## Logging Errors

### CRITICAL: No Sensitive Data

```java
// ❌ NEVER
log.error("Login failed for password: {}", password);

// ✅ Good
log.error("Login failed for user: {}", userId);
```

### REQUIRED: Log with Context

```java
// ✅ Include relevant IDs and trace context
log.error("Order processing failed. orderId={}, userId={}", orderId, userId, exception);
```

### REQUIRED: Appropriate Log Levels

| Level | When |
|-------|------|
| `ERROR` | Unexpected failures, needs attention |
| `WARN` | Expected failures (validation, not found) |
| `INFO` | Business events |
| `DEBUG` | Troubleshooting details |

```java
// Validation failure — expected, not an error
log.warn("Validation failed for order creation: {}", validationErrors);

// Unexpected database failure — error
log.error("Database connection failed", exception);
```

---

## External Service Errors

### REQUIRED: Wrap External Exceptions

```java
class ExternalServiceException extends RuntimeException {
    private final String serviceName;
    private final int statusCode;

    // Don't expose raw external errors to clients
}

// In HTTP client
try {
    return restClient.get(url);
} catch (RestClientException e) {
    throw new ExternalServiceException("payment-service", e);
}
```

### RECOMMENDED: Circuit Breaker

Unreliable externals:

```java
@CircuitBreaker(name = "payment", fallbackMethod = "fallback")
public PaymentResult processPayment(PaymentRequest request) {
    return paymentClient.process(request);
}

public PaymentResult fallback(PaymentRequest request, Exception e) {
    log.warn("Payment service unavailable, queuing for retry");
    return PaymentResult.queued();
}
```

---

## Anti-Patterns

### CRITICAL: Don't Swallow Exceptions

```java
// ❌ NEVER — silently swallowing
try {
    process();
} catch (Exception e) {
    // nothing
}

// ❌ NEVER — log and ignore
try {
    process();
} catch (Exception e) {
    log.error("Error", e);  // Then what?
}

// ✅ Handle or propagate
try {
    process();
} catch (SpecificException e) {
    return fallbackBehavior();
}
```

### CRITICAL: Don't Catch Generic Exception

```java
// ❌ Avoid
try {
    process();
} catch (Exception e) { }

// ✅ Catch specific exceptions
try {
    process();
} catch (OrderNotFoundException e) {
    return notFound();
} catch (ValidationException e) {
    return badRequest(e.getErrors());
}
```

---

## Quick Reference

| Rule | Priority |
|------|----------|
| No sensitive data in logs | CRITICAL |
| Don't swallow exceptions | CRITICAL |
| Don't catch generic Exception | CRITICAL |
| Domain-specific exceptions | REQUIRED |
| Consistent error response format | REQUIRED |
| Global exception handler | REQUIRED |
| HTTP status mapping | REQUIRED |
| Field-level validation details | REQUIRED |
| Log with context (IDs) | REQUIRED |
| Appropriate log levels | REQUIRED |
| Wrap external exceptions | REQUIRED |
| Exception hierarchy | RECOMMENDED |
| Circuit breaker for externals | RECOMMENDED |
