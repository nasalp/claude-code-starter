---
paths:
  - "**/*.java"
---

# Controller Rules

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deployment, no exceptions |
| **REQUIRED** | Must follow unless explicitly overridden |

---

## CRITICAL: Controllers Are Thin Layers

Controllers MUST only:
1. Accept the HTTP request (path params, query params, request body)
2. Call a service method
3. Convert the service result into an HTTP response

Controllers MUST NOT contain:
- Business logic
- Data transformation logic beyond simple response mapping
- Multiple service calls orchestrated together
- Conditional logic based on business rules

```java
// GOOD - thin controller
@GetMapping("/{id}")
ResponseEntity<OrderResponse> getOrder(@PathVariable String id) {
    Order order = orderService.getOrder(id);
    return ResponseEntity.ok(OrderResponse.from(order));
}

// BAD - business logic in controller
@GetMapping("/{id}")
ResponseEntity<OrderResponse> getOrder(@PathVariable String id) {
    Order order = orderRepository.findById(id).orElseThrow();
    if (order.getStatus() == CANCELLED) {
        throw new OrderCancelledException(id);
    }
    var discount = discountService.calculate(order);
    order.applyDiscount(discount);
    return ResponseEntity.ok(OrderResponse.from(order));
}
```

---

## CRITICAL: No Static Security Context Access in Controllers

Controllers MUST NOT make static calls to retrieve security information:
- `SecurityContextHolder.getContext()`
- `SecurityContextUtils.getCurrentUserId()`
- Any static utility that pulls from the security context

### Allowed: Method-Injected Security Info

Controllers MAY receive security information via method injection (`@AuthenticationPrincipal`, `OAuth2User`, `Jwt`, `Authentication` as method parameters) and pass it to services.

```java
// GOOD - security info injected and passed to service
@GetMapping("/entities")
ResponseEntity<EntitiesResponse> getEntities(@AuthenticationPrincipal OAuth2User principal) {
    String userId = principal.getAttribute("sub");
    String email = principal.getAttribute("email");
    var entities = platformSelectionService.getEntities(userId);
    return ResponseEntity.ok(entities);
}

// BAD - static call to security context
@GetMapping("/entities")
ResponseEntity<EntitiesResponse> getEntities() {
    String userId = SecurityContextUtils.getCurrentUserId();
    var entities = platformSelectionService.getEntities(userId);
    return ResponseEntity.ok(entities);
}

// BAD - static SecurityContextHolder access
@GetMapping("/entities")
ResponseEntity<EntitiesResponse> getEntities() {
    var auth = SecurityContextHolder.getContext().getAuthentication();
    var entities = platformSelectionService.getEntities(auth.getName());
    return ResponseEntity.ok(entities);
}
```

---

## REQUIRED: Response Mapping Only

If a response needs transformation from a domain object, use:
- A static factory method on the response DTO: `Response.from(domainObject)`
- Or a simple inline mapping in the controller

Do NOT create separate "mapper" classes for simple conversions.

---

## Enforcement

Enforced by ArchUnit tests:
- `ControllerArchitectureTest` verifies no controller imports `SecurityContextHolder` or `SecurityContextUtils`
- Any violation fails the build
- Method-injected security parameters (`@AuthenticationPrincipal`, `Jwt`, `Authentication`) are allowed and not flagged

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| ArchUnit test fails with `SecurityContextHolder import` | Controller uses static security access | Replace with `@AuthenticationPrincipal` method parameter |
| `@AuthenticationPrincipal` is null in test | MockMvc not configured with security context | Use `@WithMockUser` or pass `.with(jwt())` in MockMvc request |
| Controller returns 500 instead of 400 on bad input | Missing `@Valid` on `@RequestBody` parameter | Add `@Valid` before `@RequestBody` |
| `Response.from()` throws NPE | Domain object has null fields not expected by DTO | Add null check in factory method, or fix the service to return complete objects |

---

## Quick Reference

| Rule | Priority |
|------|----------|
| Controllers are thin layers | CRITICAL |
| No static security context access (`SecurityContextHolder`, `SecurityContextUtils`) | CRITICAL |
| Method-injected security info is allowed (`@AuthenticationPrincipal`, `OAuth2User`) | CRITICAL |
| Response mapping only | REQUIRED |

> Rationale (Why/Calibration/Cross-refs): `docs/rule-rationale/java__controllers.md`
