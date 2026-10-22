---
paths:
  - "**/*.java"
---

# Observability Rules

Observability is first-class.

## Required Components

### Mandatory Dependencies

```xml
<!-- Maven -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-core</artifactId>
</dependency>
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-observation</artifactId>
</dependency>
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>context-propagation</artifactId>
</dependency>
```

```groovy
// Gradle
implementation 'io.micrometer:micrometer-core'
implementation 'io.micrometer:micrometer-observation'
implementation 'io.micrometer:context-propagation'
```

---

## Context Propagation (CRITICAL)

### Auto-Configuration
Spring Boot auto-configures context propagation when the library is on classpath.

### Verification
After async execution, check logs include trace IDs. If missing → executor not wrapped.

---

## Async Code Requirements

### ALWAYS Use Spring-Managed Executors

```java
// ✅ CORRECT - Spring-managed executor
@Autowired
private Executor taskExecutor;

CompletableFuture.runAsync(() -> process(), taskExecutor);

// ❌ WRONG - default executor loses context
CompletableFuture.runAsync(() -> process());

// ❌ WRONG - unmanaged executor
var executor = Executors.newFixedThreadPool(10);
CompletableFuture.runAsync(() -> process(), executor);
```

### Executor Configuration

```java
@Configuration
@EnableAsync
class AsyncConfig {

    @Bean
    public Executor taskExecutor() {
        var executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(5);
        executor.setMaxPoolSize(10);
        executor.setQueueCapacity(100);
        executor.setThreadNamePrefix("async-");
        executor.initialize();
        return executor;
        // Auto-wrapped by context-propagation
    }
}
```

---

## Metrics

### Business Metrics
Every business-critical flow MUST have metrics:

```java
@Autowired
private MeterRegistry registry;

void processOrder(Order order) {
    var timer = Timer.start(registry);

    try {
        // Process order
        registry.counter("orders.processed", "status", "success").increment();
    } catch (Exception e) {
        registry.counter("orders.processed", "status", "failure").increment();
        throw e;
    } finally {
        timer.stop(registry.timer("orders.processing.time"));
    }
}
```

### Cache Metrics
```java
Cache<String, User> cache = Caffeine.newBuilder()
    .maximumSize(10_000)
    .recordStats()  // Enables metrics
    .build();

// Caffeine stats auto-exported to Micrometer
```

### Queue Metrics
```java
@Bean
public Executor taskExecutor(MeterRegistry registry) {
    var executor = new ThreadPoolTaskExecutor();
    executor.setCorePoolSize(5);
    executor.setMaxPoolSize(10);
    executor.setQueueCapacity(100);
    executor.initialize();

    // Instrument the executor
    return ExecutorServiceMetrics.monitor(
        registry,
        executor.getThreadPoolExecutor(),
        "taskExecutor"
    );
}
```

---

## Tracing

### Inbound/Outbound Boundaries
Trace context MUST be:
- Received on inbound requests (HTTP, messaging)
- Propagated to outbound calls (HTTP clients, messaging)
- Preserved across async boundaries

### Log Correlation
```yaml
logging:
  pattern:
    console: "%d{yyyy-MM-dd HH:mm:ss} [%X{traceId}/%X{spanId}] %-5level %logger{36} - %msg%n"
```

### Signals
Always include:
- Success signals
- Failure signals
- Latency

---

## Observation API

```java
@Autowired
private ObservationRegistry observationRegistry;

void processOrder(Order order) {
    Observation.createNotStarted("order.processing", observationRegistry)
        .lowCardinalityKeyValue("orderType", order.getType().name())
        .observe(() -> {
            // Process order
        });
}
```

---

## Health Checks

### Kubernetes Probes
```yaml
management:
  endpoint:
    health:
      probes:
        enabled: true
  health:
    livenessState:
      enabled: true
    readinessState:
      enabled: true
```

### Custom Health Indicators
```java
@Component
class ExternalServiceHealthIndicator implements HealthIndicator {

    @Override
    public Health health() {
        if (isServiceAvailable()) {
            return Health.up().build();
        }
        return Health.down()
            .withDetail("reason", "Service unavailable")
            .build();
    }
}
```

---

## Alerting Guidelines

### Alert On
- Cache hit ratio dropping below threshold
- Queue size approaching capacity
- Eviction rates spiking
- Error rates above threshold
- Latency p99 exceeding SLO

### Monitor
- Request rate
- Error rate
- Duration (p50, p95, p99)
- Queue depth
- Cache stats

---

## Checklist

- [ ] Context-propagation on classpath
- [ ] Async code uses Spring-managed executors
- [ ] Business flows have metrics
- [ ] Caches have `recordStats()` enabled
- [ ] Queues are instrumented
- [ ] Logs include trace IDs
- [ ] Health probes configured
- [ ] Custom health indicators for external deps

> Rationale (Why/Calibration/Cross-refs): `docs/rule-rationale/java__observability.md`
