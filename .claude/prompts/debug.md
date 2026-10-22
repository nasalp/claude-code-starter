# Prompt: Debug

## Template

```
Help debug this issue.

Error/Symptom:
<describe what's happening>

Expected:
<what should happen>

Code:
<relevant code or file path>

Stack trace (if available):
<paste stack trace>

What I've tried:
<list attempts>

Help me:
1. Identify the root cause
2. Explain why it's happening
3. Provide a fix
4. Suggest how to prevent similar issues
```

## Example

```
Help debug this issue.

Error: NullPointerException when creating order

Expected: Order should be created successfully

Code:
@PostMapping("/orders")
public Order createOrder(@RequestBody CreateOrderRequest request) {
    var customer = customerRepository.findById(request.getCustomerId());
    var order = new Order(customer.getId(), request.getItems());
    return orderRepository.save(order);
}

Stack trace:
java.lang.NullPointerException
    at OrderController.createOrder(OrderController.java:25)

What I've tried:
- Verified customer exists in database
- Checked request body is not null
```

## Expected Output

```markdown
## Root Cause

`customerRepository.findById()` returns `Optional<Customer>`, not `Customer`.
Calling `.getId()` on the Optional (not the Customer) likely returns null or throws.

## Why It's Happening

```java
// This returns Optional<Customer>, not Customer
var customer = customerRepository.findById(request.getCustomerId());

// This calls Optional.getId() which doesn't exist,
// or if it somehow compiles, customer might be empty
var order = new Order(customer.getId(), ...);  // NPE here
```

## Fix

```java
@PostMapping("/orders")
public Order createOrder(@RequestBody @Valid CreateOrderRequest request) {
    var customer = customerRepository.findById(request.getCustomerId())
        .orElseThrow(() -> new CustomerNotFoundException(request.getCustomerId()));
    var order = new Order(customer.getId(), request.getItems());
    return orderRepository.save(order);
}
```

## Prevention

1. **Use `orElseThrow()`** — Always handle empty Optionals explicitly
2. **Add `@Valid`** — Validate request before processing
3. **IDE warnings** — Enable "Optional misuse" inspections
4. **Write test** — Test case for non-existent customer
```
