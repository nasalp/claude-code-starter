# Prompt: Explain

## Template

```
Explain this code.

Code:
<paste code or file path>

Explain:
1. What it does (high-level purpose)
2. How it works (step by step)
3. Key concepts used
4. Potential issues or improvements
```

## Example

```
Explain this code:

@Transactional
@Retryable(maxAttempts = 3, backoff = @Backoff(delay = 1000))
public Order processPayment(OrderId orderId) {
    var order = orderRepository.findById(orderId)
        .orElseThrow(() -> new OrderNotFoundException(orderId));
    var result = paymentClient.charge(order.getPaymentMethod(), order.getTotal());
    if (result.isSuccessful()) {
        order.markAsPaid(result.getTransactionId());
        orderRepository.save(order);
        eventPublisher.publish(new OrderPaidEvent(orderId));
    } else {
        throw new PaymentFailedException(result.getErrorMessage());
    }
    return order;
}
```

## Expected Output

```markdown
## What It Does

Processes payment for an order: charges the customer's payment method and updates the order status to "paid" if successful.

## How It Works

1. **Find order** — Loads order from database, throws if not found
2. **Charge payment** — Calls external payment service
3. **If successful:**
   - Marks order as paid (with transaction ID)
   - Saves updated order
   - Publishes event for other services
4. **If failed:** Throws exception (triggers retry)

## Key Concepts

| Concept | Purpose |
|---------|---------|
| `@Transactional` | All DB operations in single transaction; rolls back on exception |
| `@Retryable` | Retries up to 3 times with 1s delay if exception thrown |
| `@Backoff` | Wait time between retries |
| Event publishing | Notifies other services asynchronously |

## Data Flow

```
findOrder → chargePayment → updateOrder → publishEvent
                ↓ (if fails)
            retry (up to 3x)
                ↓ (if still fails)
            rollback transaction
```

## Potential Issues

1. **Non-idempotent** — Retry could double-charge if payment succeeds but save fails
   - Fix: Check for existing transaction before charging

2. **Event after commit** — Event published inside transaction; if commit fails, event already sent
   - Fix: Use `@TransactionalEventListener(phase = AFTER_COMMIT)`

3. **No timeout** — Payment call could hang forever
   - Fix: Configure timeout on payment client
```
