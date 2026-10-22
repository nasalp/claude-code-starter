# Contract tests MUST NOT use `@SpringBootTest(webEnvironment = RANDOM_PORT)`

## Priority

| Priority | Meaning |
|---|---|
| **CRITICAL** | Blocks deployment, no exceptions |

## Rule

Spring Cloud Contract (and any other contract-style HTTP verification) base
class MUST NOT extend a `@SpringBootTest` with `webEnvironment = RANDOM_PORT`
(or `DEFINED_PORT`). Generated contract tests MUST exercise the web layer
via `MockMvc` (servlet) or `WebTestClient` (WebFlux) bound directly to the
application context — **no real port binding, no full Netty/Tomcat server,
no live HTTP socket.**

## How to do it right

**No Spring context. No autowire. No bean lookup.** Construct the
controller under test directly, mock its collaborators with Mockito,
and bind the in-memory test client to that controller instance.
Contract tests are about WIRE SHAPE — `given THIS request, return THIS
status + body`. Nothing in that goal requires loading a Spring context.

### Spring MVC (servlet) — standalone

```java
public abstract class ContractTestBase {
    protected final SomeService someService = Mockito.mock(SomeService.class);
    protected final MyController myController = new MyController(someService);

    @BeforeEach
    void wire() {
        RestAssuredMockMvc.standaloneSetup(this.myController);
    }
}
```

SCC pom config:

```xml
<testMode>MOCKMVC</testMode>
```

### Spring WebFlux (reactive) — standalone

```java
public abstract class ContractTestBase {
    protected final ClientStore clientStore = Mockito.mock(ClientStore.class);
    protected final OAuthAuthorizeController authorize =
        new OAuthAuthorizeController(this.clientStore, ...);

    protected final WebTestClient webTestClient =
        WebTestClient.bindToController(this.authorize)
            // any additional controllers your contracts cover
            .build();
}
```

SCC pom config:

```xml
<testMode>WEBTESTCLIENT</testMode>
```

`WebTestClient.bindToController(...)` and
`RestAssuredMockMvc.standaloneSetup(...)` both bypass the Spring context
entirely. A contract test class starts in **milliseconds**, not the 5–30s
of a `@SpringBootTest`. No Redis, no JWT secret, no auth filter, no
component-scan — just the request → controller → response shape that
the contract actually pins.

### When you genuinely need other beans

If a contract verifies behavior that depends on a Spring-managed
collaborator (rare for pure HTTP-shape contracts), construct that bean
yourself or mock it. The line between "I need a real bean" and "I
should be writing an integration test instead" is bright: contracts are
wire-shape only.

If you find yourself reaching for `@SpringBootTest`, you're probably
writing the wrong kind of test.

### Last resort: full context (do NOT use for SCC)

Only acceptable for end-to-end / integration tests, NOT contract tests:

```java
// Acceptable for E2E only — full app + real port
@SpringBootTest(webEnvironment = RANDOM_PORT)
public abstract class FullStackE2EBase { ... }
```

These tests should live under `*E2ETest.java` and be excluded from
fast CI, not commingled with SCC contracts.

## Anti-patterns (specifically banned)

```java
// ❌ NEVER — full Netty boot + real port binding for a contract test
@SpringBootTest(classes = MyApp.class, webEnvironment = RANDOM_PORT)
public abstract class ContractTestBase {
    @LocalServerPort int port;
    @BeforeEach void wire() {
        RestAssured.baseURI = "http://localhost";
        RestAssured.port = this.port;
    }
}

// ❌ NEVER — DEFINED_PORT is even worse (collision risk under parallel)
@SpringBootTest(webEnvironment = DEFINED_PORT)

// ❌ NEVER — adding @MockBean(RateLimitWebFilter.class) to "make
//   RANDOM_PORT work without Redis" is a tell that you took the wrong
//   approach. The fix is MockMvc / WebTestClient, not stripping the
//   filter chain.
```

## Enforcement

ArchUnit (or a simpler `grep` gate in CI):

```java
@ArchTest
static final ArchRule contract_tests_must_not_use_random_port =
    noClasses()
        .that().resideInAnyPackage("..contract..")
        .should().beAnnotatedWith(SpringBootTest.class)
        .andShould(new ArchCondition<JavaClass>("not bind RANDOM_PORT") {
            @Override
            public void check(JavaClass clazz, ConditionEvents events) {
                Optional<JavaAnnotation<?>> ann = clazz.tryGetAnnotationOfType(SpringBootTest.class);
                ann.ifPresent(a -> {
                    Object env = a.get("webEnvironment").orElse(null);
                    if ("RANDOM_PORT".equals(String.valueOf(env)) ||
                        "DEFINED_PORT".equals(String.valueOf(env))) {
                        events.add(SimpleConditionEvent.violated(
                            clazz, "contract test uses real port binding"));
                    }
                });
            }
        });
```

Or a CI shell guard:

```bash
if grep -rE 'webEnvironment\s*=\s*(RANDOM_PORT|DEFINED_PORT)' \
        src/test/java/**/contract/ 2>/dev/null; then
    echo "ERROR: contract tests must use MockMvc/WebTestClient, not real ports"
    exit 1
fi
```

## Quick reference

| Rule | Priority |
|---|---|
| No `@SpringBootTest(RANDOM_PORT)` or `(DEFINED_PORT)` in contract test base classes | CRITICAL |
| Spring MVC → `@AutoConfigureMockMvc` + `RestAssuredMockMvc.mockMvc(...)` + SCC `<testMode>MOCKMVC</testMode>` | CRITICAL |
| Spring WebFlux → `@AutoConfigureWebTestClient` + `WebTestClient` + SCC `<testMode>WEBTESTCLIENT</testMode>` | CRITICAL |
| Prefer `@WebMvcTest` / `@WebFluxTest` slices over full `@SpringBootTest(MOCK)` when feasible | RECOMMENDED |
| ArchUnit (or grep) gate that fails the build on real-port contract tests | REQUIRED |

> Rationale (Why/Calibration/Cross-refs): `docs/rule-rationale/java__contract-tests-must-not-use-random-port.md`
