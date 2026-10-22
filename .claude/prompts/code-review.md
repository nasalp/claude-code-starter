# Prompt: Code Review

## Template

```
Review this code for quality and best practices.

Check:
1. Code style (KISS, YAGNI, DRY)
2. Method/class size
3. Naming clarity
4. Error handling
5. Testability
6. Performance concerns

Code:
<paste code or file path>

Categorize feedback as:
- REQUIRED: Must fix
- SUGGESTED: Should consider
- NITPICK: Minor improvement
```

## Example

```
Review this code:

public class OrderManager {
    public void processOrder(Order o) {
        if (o != null) {
            if (o.getItems() != null) {
                if (o.getItems().size() > 0) {
                    BigDecimal total = new BigDecimal(0);
                    for (int i = 0; i < o.getItems().size(); i++) {
                        OrderItem item = o.getItems().get(i);
                        total = total.add(item.getPrice().multiply(
                            new BigDecimal(item.getQuantity())));
                    }
                    o.setTotal(total);
                    orderRepository.save(o);
                    emailService.sendConfirmation(o.getCustomerEmail(), o);
                }
            }
        }
    }
}
```

## Expected Output

```markdown
## Code Review

### REQUIRED

**Nested null checks** — Use guard clauses
```java
void processOrder(Order order) {
    if (order == null || order.getItems().isEmpty()) {
        return;
    }
    // rest of logic
}
```

**Unclear naming** — `o` should be `order`

**FQN/verbose BigDecimal** — Use `BigDecimal.ZERO`

### SUGGESTED

**Method too long** — Extract `calculateTotal()` and `notifyCustomer()`

**Use streams** — Replace for-loop with stream
```java
var total = order.getItems().stream()
    .map(item -> item.getPrice().multiply(BigDecimal.valueOf(item.getQuantity())))
    .reduce(BigDecimal.ZERO, BigDecimal::add);
```

**Class name** — `OrderManager` is vague, prefer `OrderService`

### NITPICK

**Empty line** — Remove blank line in method
```
