---
name: otel-node-sdk-traps
description: Survive Node.js OpenTelemetry SDK silent failures — empty spanProcessors disabling traces, setupMetrics ordering, Sentry coexistence, Prometheus unit-suffix gaps, and gRPC vs HTTP port routing
origin: ECC
triggers: NodeSDK, sdk.start, OTLPTraceExporter, PrometheusExporter, RuntimeNodeInstrumentation, HttpInstrumentation, Sentry skipOpenTelemetrySetup, SentrySpanProcessor, otel-metrics.js, instrument.js, OTELMETRICSEXPORTER, OTELEXPORTEROTLPENDPOINT
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.cjs"
  - "**/*.mjs"
---
# OpenTelemetry Node.js SDK Traps

Six silent-failure modes that turn a "configured" Node OTel pipeline into a noop. Every one of these passed code review in production and was only caught by running an end-to-end LGTM (Loki/Grafana/Tempo/Mimir) pipeline. If you are wiring `@opentelemetry/sdk-node`, Sentry, and a Prometheus exporter in the same Node service, read this first.

## When to use

- You are configuring `NodeSDK` in a Node service that also uses `@sentry/node`.
- You see "TracerProvider: NOOP" logs, empty Tempo, or `NonRecordingSpan` in a debugger.
- You are debugging "metrics endpoint returns nothing" or "PromQL doesn't match the metric name we ship".
- You replaced `OtlpHttpExporter` with the gRPC exporter and traces still don't arrive.

## When NOT to use

- Pure browser OpenTelemetry (different SDK, different traps).
- A managed agent collector setup where the JS SDK is not in your hands.
- Sentry-only setups with no NodeSDK — none of these traps apply.

## The pattern

These six traps must all be defended in the same boot file. The canonical sequence in the reference project is `services/dashboard-v2/otel-metrics.js` and `services/dashboard-v2/instrument.js`.

### Trap 1 — empty `spanProcessors: []` disables tracing

Passing an empty array tells `NodeSDK` "the user manages span processors" and it does NOT register the default `BatchSpanProcessor(traceExporter)`. `trace.getTracer().startSpan()` then returns `NonRecordingSpan` — every span is a noop.

Spread the key only when non-empty:

```javascript
const spanProcessors = [];
if (process.env.SENTRY_DSN) {
  const { SentrySpanProcessor } = require('@sentry/opentelemetry');
  spanProcessors.push(new SentrySpanProcessor());
}

const sdk = new NodeSDK({
  resource: resourceFromAttributes({ [ATTR_SERVICE_NAME]: serviceName }),
  traceExporter: new OTLPTraceExporter({ url: `${otlpEndpoint}/v1/traces` }),
  // Only pass spanProcessors if non-empty — empty array disables TracerProvider
  ...(spanProcessors.length > 0 && { spanProcessors }),
  instrumentations: [/* ... */],
});
```

### Trap 2 — `setupMetrics()` must run BEFORE `sdk.start()`

`RuntimeNodeInstrumentation` and `HttpInstrumentation` create OTel instruments at `sdk.start()` time. Those instruments bind to whatever `MeterProvider` is global at that exact moment. If you set `OTEL_METRICS_EXPORTER=none` to prevent NodeSDK from registering its own MeterProvider, the instruments bind to the noop provider — and they will never re-bind when your Prometheus MeterProvider is registered later.

```javascript
process.env.OTEL_METRICS_EXPORTER = 'none';
// 1. Register PrometheusExporter MeterProvider FIRST
require('@example/observability').setupMetrics('dashboard-v2');
// 2. THEN start NodeSDK so auto-instrumentation binds to PrometheusExporter
const sdk = new NodeSDK({ /* ... */ });
sdk.start();
```

### Trap 3 — Sentry overwrites the TracerProvider unless `skipOpenTelemetrySetup: true`

Sentry v10+ registers its own TracerProvider in `Sentry.init()`. Even with an empty DSN, `require('@sentry/node')` followed by `Sentry.init()` replaces your real provider with a noop one. Pass `skipOpenTelemetrySetup: true` and route spans into Sentry through `SentrySpanProcessor` from `@sentry/opentelemetry`.

```javascript
Sentry.init({
  dsn: process.env.SENTRY_DSN,
  skipOpenTelemetrySetup: true,         // critical
  // ...
});
```

### Trap 4 — PrometheusExporter v0.215 omits unit suffixes

Dashboards written for Java Micrometer often expect `http_server_request_duration_seconds_count`. The Node `PrometheusExporter`'s `sanitizePrometheusMetricName()` only converts dots to underscores and adds `_total` for counters — no `_seconds`, `_bytes`, etc. The actual scraped name is `http_server_request_duration_count`. Update PromQL or rename instruments rather than patching the exporter.

### Trap 5 — gRPC vs HTTP routing on `grafana/otel-lgtm`

`grafana/otel-lgtm` exposes OTLP HTTP on `:4318` and gRPC on `:4317`. When mapped through Docker as `14318→4318` and `14317→4317`, sending HTTP from the host returns `{}` instead of `{"partialSuccess":{}}` because something inside the container intercepts host-bound HTTP. gRPC works. Use `@opentelemetry/exporter-trace-otlp-grpc` for host-to-LGTM, or run the exporter from inside the container.

Also: collector exporter names must match between the `exporters:` block and `service.pipelines.*.exporters:` exactly — `otlp_http/traces` (underscore) vs `otlphttp/traces` (no underscore) silently sends to nothing.

### Trap 6 — `localhost` resolves to IPv6 on production Ubuntu

Production Ubuntu resolves `localhost` to `::1` (IPv6) but Docker only binds IPv4 port mappings. Replace it before constructing the exporter:

```javascript
const otlpEndpoint = (process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://127.0.0.1:4318')
  .replace('localhost', '127.0.0.1');
```

## Common gotchas / variants

- `OTEL_METRICS_EXPORTER=none` is what lets you own the MeterProvider, but the `OTEL_LOGS_EXPORTER` env var should NOT be force-disabled if you still want OTel logs flowing.
- `OTEL_SEMCONV_STABILITY_OPT_IN=http` is required for stable HTTP semantic conventions; without it metric/attribute names drift between SDK versions.
- Forbidden env vars in the reference project that cause double-registration: `OTEL_TRACES_EXPORTER`, `OTEL_LOGS_EXPORTER`, `OTEL_RESOURCE_ATTRIBUTES`, `OTEL_NODE_RESOURCE_DETECTORS`, `NODE_OPTIONS` (when it injects another agent).
- Auto-instrumentation patches modules at `sdk.start()`. Anything `require`d before that — including your logger — won't be instrumented.
- For HTTP routes, set `http.route` from the Express route template via `applyCustomAttributesOnSpan`. Without it, dashboards group everything under no-route and look empty.
- Filter cloud metadata service spans (`169.254.169.254`, `metadata.google.internal`) and observability self-traffic (`:4040`, `:4317`, `:4318`, `:9100`, `:12345`) with a wrapping span processor.

## Verification

After boot, prove the TracerProvider is real (not noop):

```javascript
const { trace: traceApi } = require('@opentelemetry/api');
const verifySpan = traceApi.getTracer('verify').startSpan('verify');
const isReal = verifySpan.constructor.name !== 'NonRecordingSpan';
verifySpan.end();
console.log(`[OTel] TracerProvider: ${isReal ? 'REAL' : 'NOOP'}`);
```

Other checks:

- `curl http://localhost:9464/metrics | head` — actual Prometheus names visible.
- `grpcurl -plaintext localhost:14317 ...` or send one trace; confirm `{"partialSuccess":{}}` in the response body, not `{}`.
- `docker logs grafana-otel-lgtm | grep traces_received` to confirm the collector pipeline.
