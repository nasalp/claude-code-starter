# Prompt: Refactor

## Template

```
Refactor this code to improve quality.

Goals:
- Maintain exact same behavior
- Improve readability
- Follow KISS, YAGNI, DRY
- Keep methods short (~10-15 lines)
- Keep classes focused (single responsibility)

Constraints:
- Don't change public API
- Don't change test behavior
- Preserve all functionality

Code:
<paste code or file path>

Show:
1. Refactored code
2. What changed and why
3. How to verify behavior unchanged
```

## Example

```
Refactor this code:

public BigDecimal calculateOrderTotal(Order order, String discountCode, boolean isPremium) {
    BigDecimal total = new BigDecimal("0");
    for (OrderItem item : order.getItems()) {
        BigDecimal itemTotal = item.getPrice().multiply(new BigDecimal(item.getQuantity()));
        total = total.add(itemTotal);
    }
    if (discountCode != null && !discountCode.isEmpty()) {
        if (discountCode.equals("SAVE10")) {
            total = total.multiply(new BigDecimal("0.9"));
        } else if (discountCode.equals("SAVE20")) {
            total = total.multiply(new BigDecimal("0.8"));
        } else if (discountCode.equals("HALF")) {
            total = total.multiply(new BigDecimal("0.5"));
        }
    }
    if (isPremium) {
        total = total.multiply(new BigDecimal("0.95"));
    }
    return total;
}
```

## Expected Output

```java
// Refactored
BigDecimal calculateOrderTotal(Order order, String discountCode, boolean isPremium) {
    var subtotal = calculateSubtotal(order);
    var afterDiscount = applyDiscount(subtotal, discountCode);
    return applyPremiumDiscount(afterDiscount, isPremium);
}

private BigDecimal calculateSubtotal(Order order) {
    return order.getItems().stream()
        .map(this::itemTotal)
        .reduce(BigDecimal.ZERO, BigDecimal::add);
}

private BigDecimal itemTotal(OrderItem item) {
    return item.getPrice().multiply(BigDecimal.valueOf(item.getQuantity()));
}

private BigDecimal applyDiscount(BigDecimal amount, String code) {
    if (code == null || code.isEmpty()) {
        return amount;
    }
    var multiplier = switch (code) {
        case "SAVE10" -> new BigDecimal("0.9");
        case "SAVE20" -> new BigDecimal("0.8");
        case "HALF" -> new BigDecimal("0.5");
        default -> BigDecimal.ONE;
    };
    return amount.multiply(multiplier);
}

private BigDecimal applyPremiumDiscount(BigDecimal amount, boolean isPremium) {
    return isPremium ? amount.multiply(new BigDecimal("0.95")) : amount;
}
```

**Changes:**
1. Extracted calculation into small, focused methods
2. Used streams for item total
3. Used switch expression for discount codes
4. Each method does one thing

**Verification:**
- Same inputs produce same outputs
- Run existing tests
- No public API changes
