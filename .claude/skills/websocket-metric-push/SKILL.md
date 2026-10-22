---
name: websocket-metric-push
description: Push live metric snapshots to browsers via Spring STOMP-over-WebSocket — record payload + ConcurrentHashMap snapshot store + @Scheduled @SchedulerLock broadcaster + React stompjs client with reconnect
origin: ECC
triggers: WebSocket, STOMP, SimpMessagingTemplate, useMetricStream, live dashboard, real-time metrics, MetricSnapshot, EnableWebSocketMessageBroker, SockJS
paths:
  - "**/*.java"
  - "**/*.ts"
  - "**/*.tsx"
---
# WebSocket Metric Push (STOMP + React)

End-to-end pattern for pushing periodic metric updates from a Spring Boot service to React dashboards. The backend uses Spring's simple in-memory STOMP broker (no RabbitMQ/Kafka required), a `ConcurrentHashMap` snapshot store readable by other beans (e.g. goal scoring), and `@Scheduled` + `@SchedulerLock` (ShedLock) so only one node in a clustered deployment broadcasts. The frontend uses `@stomp/stompjs` with auto-reconnect and protocol-aware (ws/wss) URL derivation from `window.location`.

## When to use

- You need browser-pushed updates (live dashboards, sticky tickers) at 1–10 s cadence.
- Updates are broadcast — every connected client gets the same payload. No per-user filtering.
- Payload is small (a few fields, < 1 KB) and the cadence is fixed.
- You can afford an in-memory broker. For multi-node fan-out, you swap `enableSimpleBroker` for `enableStompBrokerRelay` to RabbitMQ.

## When NOT to use

- Per-user/per-tenant streams. Use Server-Sent Events (SSE) keyed by user, or STOMP user-destination (`/user/queue/...`) — but then `@SchedulerLock` doesn't apply because every node has different subscribers.
- High-frequency updates (>20 Hz). Use raw WebSocket binary, not STOMP — the framing overhead dominates.
- Internet-facing public dashboard with thousands of clients. The simple broker is in-memory; a single node holds every subscription. Use a relay broker.
- Stateless replay needed (client reconnects and wants the last hour). Use Kafka + a frontend that consumes a topic.

## The pattern

### Backend: payload, store, broadcaster, config

**`MetricSnapshot.java`** — immutable record, serialized by Jackson:

```java
public record MetricSnapshot(String metricId, BigDecimal value, Instant timestamp) {}
```

**`MetricSnapshotStore.java`** — `@Component` reading the latest broadcast value:

```java
@Component
public class MetricSnapshotStore {
    private final ConcurrentHashMap<String, BigDecimal> latestValues = new ConcurrentHashMap<>();

    public void update(String metricId, BigDecimal value) {
        this.latestValues.put(metricId, value);
    }

    public Map<String, BigDecimal> getLatest() {
        return Map.copyOf(this.latestValues);   // immutable defensive copy
    }
}
```

`Map.copyOf` returns an unmodifiable snapshot, so callers (e.g. `CompanyPulseService` scoring goals against current values) never see a `ConcurrentModificationException` or a half-written entry.

**`MetricPushService.java`** — `@Scheduled(fixedRate = 5000)` + `@SchedulerLock`:

```java
@Component
class MetricPushService {
    private static final String TOPIC = "/topic/metrics/live";
    private static final List<String> METRIC_IDS = List.of(
        "mrr_total", "churn_rate", "nps_score",
        "trial_conversion_rate", "system_uptime_pct", "user_engagement_score");

    private final SimpMessagingTemplate messagingTemplate;
    private final MetricSnapshotStore snapshotStore;
    private final Random random = new Random();

    MetricPushService(SimpMessagingTemplate messagingTemplate, MetricSnapshotStore snapshotStore) {
        this.messagingTemplate = messagingTemplate;
        this.snapshotStore = snapshotStore;
    }

    @Scheduled(fixedRate = 5000)
    @SchedulerLock(name = "metrics.push-live", lockAtMostFor = "4s")
    void pushLiveMetrics() {
        String metricId = METRIC_IDS.get(this.random.nextInt(METRIC_IDS.size()));
        BigDecimal value = generateStubValue(metricId);
        MetricSnapshot snapshot = new MetricSnapshot(metricId, value, Instant.now());
        this.messagingTemplate.convertAndSend(TOPIC, snapshot);
        this.snapshotStore.update(snapshot.metricId(), snapshot.value());
    }
}
```

`lockAtMostFor` MUST be less than `fixedRate` so a stuck node doesn't permanently block others. `4s < 5s` here.

**`WebSocketConfig.java`** — minimal STOMP config:

```java
@Configuration
@EnableWebSocketMessageBroker
class WebSocketConfig implements WebSocketMessageBrokerConfigurer {

    @Override
    public void configureMessageBroker(MessageBrokerRegistry config) {
        config.enableSimpleBroker("/topic");
        config.setApplicationDestinationPrefixes("/app");
    }

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        registry.addEndpoint("/ws").setAllowedOriginPatterns("*").withSockJS();
    }
}
```

`/topic/**` for broadcasts, `/app/**` for client-to-server messages (unused here). SockJS gives a fallback path for browsers/proxies that strip WebSocket upgrades — important behind ALB / corporate proxies.

### Frontend: `useMetricStream.ts`

```ts
import { useEffect, useRef, useState } from 'react'
import { Client } from '@stomp/stompjs'

export interface MetricSnapshot {
  metricId: string
  value: number
  timestamp: string
}

export function useMetricStream(onSnapshot?: (snapshot: MetricSnapshot) => void) {
  const [connected, setConnected] = useState(false)
  const [lastSnapshot, setLastSnapshot] = useState<MetricSnapshot | null>(null)
  const clientRef = useRef<Client | null>(null)
  const onSnapshotRef = useRef(onSnapshot)
  onSnapshotRef.current = onSnapshot

  useEffect(() => {
    const apiBase = import.meta.env.VITE_API_URL || '/api/v1'
    const wsBase = apiBase.replace('/api/v1', '')
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const host = wsBase.startsWith('http') ? new URL(wsBase).host : window.location.host
    const brokerURL = `${protocol}//${host}/ws`

    const client = new Client({
      brokerURL,
      reconnectDelay: 5000,
      onConnect: () => {
        setConnected(true)
        client.subscribe('/topic/metrics/live', (message) => {
          try {
            const snapshot: MetricSnapshot = JSON.parse(message.body) as MetricSnapshot
            setLastSnapshot(snapshot)
            onSnapshotRef.current?.(snapshot)
          } catch { /* ignore malformed */ }
        })
      },
      onDisconnect: () => setConnected(false),
      onStompError: () => setConnected(false),
    })

    clientRef.current = client
    client.activate()
    return () => { client.deactivate(); clientRef.current = null }
  }, [])

  return { connected, lastSnapshot }
}
```

Key details:

- **Protocol derivation.** `window.location.protocol === 'https:' ? 'wss:' : 'ws:'` — never hardcode. Mixed-content browsers reject `ws://` from an `https://` origin.
- **Host derivation.** When `VITE_API_URL` is unset (production same-origin), use `window.location.host`. When it's set (dev cross-origin), parse it.
- **`onSnapshotRef`.** The callback identity changes every render. Stashing it in a ref keeps the `useEffect` deps stable (`[]`) so we don't tear down the WebSocket on every render.
- **`reconnectDelay: 5000`.** stompjs handles reconnect automatically. Don't roll your own.
- **`/* ignore malformed */`.** A single bad frame must not break the subscription.

## Common gotchas / variants

- **`SchedulerLock` requires ShedLock + a `LockProvider` bean** (JDBC, Redis, Mongo). Without a provider, the annotation is a no-op and every node broadcasts.
- **Mixed http/ws content.** If you serve the SPA over HTTPS but build `brokerURL` as `ws://`, browsers silently block. Always derive from `window.location.protocol`.
- **CORS / origin patterns.** `setAllowedOriginPatterns("*")` is fine for same-origin SockJS. If the SPA is on a different origin, narrow it to actual origins (security review).
- **SockJS vs raw WebSocket.** stompjs supports both; the server here registers SockJS (`.withSockJS()`). The frontend client uses `brokerURL: ws://...` which is the raw WebSocket transport. To use SockJS on the client, use `webSocketFactory` instead. Mismatch shows up as "404 /ws".
- **Auth.** STOMP `CONNECT` frames carry headers — pass JWT in `connectHeaders: { Authorization: 'Bearer ' + token }`. The simple broker doesn't enforce auth; add a `ChannelInterceptor` on the inbound channel to validate.
- **Unbounded subscribers.** Spring's simple broker holds every subscription in memory. For >1000 concurrent subscribers, switch to a relay broker.
- **`Random` is not cryptographically random** — fine for stub-value generation. If the broadcast is real metrics, replace with `java.security.SecureRandom` only if used for security; otherwise keep `Random`.

## Verification

- `wscat -c ws://localhost:8080/ws` opens; sending `CONNECT\naccept-version:1.2\n\n\0` returns `CONNECTED`.
- Subscribe via the React hook on two browser tabs; both receive the same snapshot every 5 s.
- Kill the backend; `connected` flips to `false`. Restart; within 5 s `connected` flips back to `true` (stompjs reconnect).
- Two backend nodes; only one logs the broadcast per tick (ShedLock works).
- `MetricSnapshotStore.getLatest()` from another bean returns the most recently broadcast value.

## References

- `frontend/src/app/hooks/useMetricStream.ts`
- ShedLock docs: https://github.com/lukas-krecan/ShedLock
- stompjs docs: https://stomp-js.github.io/stomp-websocket/
