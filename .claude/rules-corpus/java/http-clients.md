---
paths:
  - "**/*.java"
---

# HTTP Client Rules

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deployment, no exceptions |
| **REQUIRED** | Must follow unless explicitly overridden |

---

## CRITICAL: Use RestClient, Not RestTemplate

`RestTemplate` **deprecated** in Spring Boot 4.x. Always use `RestClient`.

```java
// ❌ NEVER — deprecated
@Autowired
RestTemplate restTemplate;

// ✅ ALWAYS — RestClient
@Autowired
RestClient.Builder restClientBuilder;

RestClient restClient = restClientBuilder.baseUrl("https://api.example.com").build();
```

### RestClient Usage

```java
// GET
Order order = restClient.get()
    .uri("/orders/{id}", orderId)
    .retrieve()
    .body(Order.class);

// POST
Order created = restClient.post()
    .uri("/orders")
    .contentType(MediaType.APPLICATION_JSON)
    .body(request)
    .retrieve()
    .body(Order.class);

// Error handling
Order order = restClient.get()
    .uri("/orders/{id}", orderId)
    .retrieve()
    .onStatus(HttpStatusCode::is4xxClientError, (req, res) -> {
        throw new OrderNotFoundException(orderId);
    })
    .body(Order.class);
```

---

## CRITICAL: No TestRestTemplate in Tests

`TestRestTemplate` is also deprecated. For E2E tests, use one of:

### Option 1: RestClient (preferred)

```java
@SpringBootTest(webEnvironment = RANDOM_PORT)
class MyE2ETest {

    @LocalServerPort
    int port;

    @Test
    void should_create_order() {
        RestClient client = RestClient.builder()
            .baseUrl("http://localhost:" + port)
            .build();

        ResponseEntity<Order> response = client.post()
            .uri("/api/v1/orders")
            .contentType(MediaType.APPLICATION_JSON)
            .body(request)
            .retrieve()
            .toEntity(Order.class);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    }
}
```

### Option 2: WebTestClient (reactive-style, works for MVC too)

```java
@SpringBootTest(webEnvironment = RANDOM_PORT)
@AutoConfigureWebTestClient
class MyE2ETest {

    @Autowired
    WebTestClient webTestClient;

    @Test
    void should_create_order() {
        webTestClient.post()
            .uri("/api/v1/orders")
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(request)
            .exchange()
            .expectStatus().isCreated();
    }
}
```

---

## REQUIRED: Declarative HTTP Clients

For external service calls, prefer declarative HTTP interfaces.

```java
interface PaymentClient {

    @GetExchange("/payments/{id}")
    Payment getPayment(@PathVariable String id);

    @PostExchange("/payments")
    Payment createPayment(@RequestBody PaymentRequest request);
}

// Configuration
@Bean
PaymentClient paymentClient(RestClient.Builder builder) {
    RestClient restClient = builder.baseUrl("https://payment.example.com").build();
    return HttpServiceProxyFactory
        .builderFor(RestClientAdapter.create(restClient))
        .build()
        .createClient(PaymentClient.class);
}
```

---

## Quick Reference

| Rule | Priority |
|------|----------|
| Use RestClient, not RestTemplate | CRITICAL |
| No TestRestTemplate in tests | CRITICAL |
| Declarative HTTP interfaces for externals | REQUIRED |
