---
name: spa-spring-boot-packaging
description: Package a React/Vite SPA inside a Spring Boot fat JAR using frontend-maven-plugin and a SpaForwardingConfig — including the runtime-vs-build-time env-var contract and the Paketo-strips-static gotcha
origin: ECC
triggers: SPA in Spring Boot, frontend-maven-plugin, BOOT-INF/classes/static, addViewControllers, SpaForwardingConfig, vite build, single fat jar frontend backend, paketo static stripped, VITEDEVMODE
paths:
  - "**/*.java"
  - "**/pom.xml"
  - "**/package.json"
  - "**/vite.config*"
---
# React SPA Inside Spring Boot Fat JAR

Bundle a React/Vite SPA and a Spring Boot service into a single deployable artifact. The frontend Maven module runs `npm ci` → `vitest` → `vite build`, emits `dist/` straight into `BOOT-INF/classes/static/`, and is depended on by the assembly module. A `WebMvcConfigurer` forwards SPA routes to `index.html` so deep links and refreshes don't 404. Two non-obvious traps — Paketo buildpacks dropping `static/`, and Vite baking env vars at build time — are addressed up front.

## When to use

- You are shipping a React (or any Vite/Webpack SPA) frontend behind the same origin as a Spring Boot API.
- You want one Docker image, one URL, one auth surface (ALB OIDC, Spring Security session).
- The team is comfortable with Maven multi-module reactor builds.
- The SPA needs deep linking (`/dashboard/finance`) and works under refresh — both browser refresh and direct paste of the URL.

## When NOT to use

- The SPA is deployed independently to a CDN (Cloudflare Pages, Vercel, S3+CloudFront). Then the Spring Boot service is a pure JSON API and this skill doesn't apply.
- You need per-request config baked into the bundle (multi-tenant white-label). Then build-per-tenant or runtime template-rendering.
- The SPA is large (>5 MB gzipped) and the JVM cold-start cost of serving static assets matters more than ops simplicity.

## The pattern

### 1. Frontend Maven module: `frontend/pom.xml`

Use `frontend-maven-plugin` with `<workingDirectory>` pointing at the actual `frontend/` source. Disable the inherited `spring-boot-maven-plugin` since this module is not a Spring Boot app, just a JAR carrier:

```xml
<plugin>
    <groupId>com.github.eirslett</groupId>
    <artifactId>frontend-maven-plugin</artifactId>
    <configuration>
        <workingDirectory>${project.basedir}/../frontend</workingDirectory>
        <nodeVersion>${node.version}</nodeVersion>
    </configuration>
    <executions>
        <execution><id>install-node-npm</id><goals><goal>install-node-and-npm</goal></goals></execution>
        <execution><id>npm-install</id><goals><goal>npm</goal></goals>
            <configuration><arguments>ci --silent</arguments></configuration></execution>
        <execution><id>npm-test</id><phase>test</phase><goals><goal>npm</goal></goals>
            <configuration>
                <arguments>run test</arguments>
                <skip>${frontend.skip.tests}</skip>
            </configuration></execution>
        <execution><id>npm-build</id><goals><goal>npm</goal></goals>
            <configuration><arguments>run build</arguments></configuration></execution>
    </executions>
</plugin>
<plugin>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-maven-plugin</artifactId>
    <configuration><skip>true</skip></configuration>
</plugin>
```

Configure `vite.config.ts` to emit into `frontend/target/classes/static/`. Add `${frontend.skip.tests}` flag so CI runs frontend tests in a parallel job and the `mvnd clean install` gate doesn't double-run them.

### 2. Assembly module depends on the frontend JAR

`app/pom.xml` declares both `backend` and `frontend` as dependencies. The Spring Boot Maven plugin's `repackage` goal merges them into the fat JAR. The `static/` directory ends up at `BOOT-INF/classes/static/` and Spring Boot's default `ResourceHttpRequestHandler` serves it.

### 3. SPA forwarding: `SpaForwardingConfig`

Without forwarding, refreshing `/department/finance` returns 404 because Spring Boot's resource handler can't find a matching file. The fix is `WebMvcConfigurer.addViewControllers` with a regex that excludes API and dotted (static-asset) paths:

```java
@Configuration(proxyBeanMethods = false)
class SpaForwardingConfig implements WebMvcConfigurer {
    private static final String SPA_SEGMENT =
        "(?!api|v3|actuator|swagger|docs|error)[^\\.]*";

    @Override
    public void addViewControllers(ViewControllerRegistry registry) {
        registry.addViewController("/{path:" + SPA_SEGMENT + "}")
                .setViewName("forward:/index.html");
        registry.addViewController("/{path:" + SPA_SEGMENT + "}/{sub:[^\\.]*}")
                .setViewName("forward:/index.html");
        registry.addViewController("/{path:" + SPA_SEGMENT + "}/{sub:[^\\.]*}/{rest:[^\\.]*}")
                .setViewName("forward:/index.html");
    }
}
```

The `[^\\.]*` segment excludes anything containing a dot, so `/assets/index.js`, `/favicon.ico`, etc. fall through to the static handler. The negative lookahead skips backend prefixes. Add as many depth levels as React Router actually uses — three is usually enough.

## Common gotchas / variants

### Paketo buildpacks STRIP `static/`

The Spring Boot `build-image` goal (Paketo `builder-noble-java-tiny`) slices the fat JAR into Docker layers (Application Slice 1–5). A later slice overwrites `BOOT-INF/classes/`, dropping the `static/` subdirectory. The fat JAR runs fine with `java -jar`, but `docker run` returns `NoResourceFoundException` for `/index.html`.

**Workaround:** abandon buildpacks, use a hand-written Dockerfile:

```dockerfile
FROM eclipse-temurin:25-jre-noble
WORKDIR /app
COPY target/app-*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

Wired with `exec-maven-plugin` at the `install` phase. This is a deliberate exception to a "no Dockerfile" rule when one exists — the rule predates the Paketo bug.

### Vite env vars are BUILD-TIME, not runtime

`import.meta.env.VITE_FOO` is replaced by `vite build` with the literal value in `.env`. It is **frozen into the bundle**. Setting `VITE_DEV_MODE=true` at container startup does nothing — the bundle was built without it.

**Rule:** anything that varies between deploys of the same image MUST be runtime-discovered. Patterns:

1. Probe a backend endpoint at startup (`AuthContext` calls `GET /api/v1/dev/users`; if 200, dev mode is on; if 404/403, fall back to production auth).
2. Server-render a tiny config script (`<script>window.__CONFIG__ = ${json}</script>`) into `index.html` via a Spring Boot controller that wraps `index.html`.
3. Expose a `GET /api/v1/config` endpoint and have the SPA fetch it before bootstrapping React.

`VITE_*` is only correct for values that are identical across all environments running the same build (asset paths, feature toggles for code that's compiled differently per build).

### ALB OIDC interaction

When the container sits behind an AWS ALB with OIDC, the ALB injects `x-amzn-oidc-data` (Base64 JWT). Production wires `AlbJwtFilter`; local dev wires `DevUserFilter` reading `X-Dev-User-Id`. The toggle is an env var (`APP_SECURITY_DEV_AUTH_ENABLED`) — Spring `@Profile` is also an acceptable mechanism for the same switch. Static assets must NOT require auth — `permitAll()` on `/`, `/index.html`, `/assets/**`, `/static/**`, `/favicon.ico`.

## Verification

- `unzip -l app-*.jar | grep BOOT-INF/classes/static/index.html` — file is present.
- `java -jar app-*.jar` then `curl http://localhost:8080/dashboard/finance -i` — returns 200 + the SPA HTML, not 404.
- `curl http://localhost:8080/assets/index-XXX.js -i` — returns 200 + JS, not the SPA HTML (forwarding regex excludes dotted paths).
- `docker build -t app:test app/ && docker run -p 8080:8080 app:test` then refresh `/dashboard` in a browser — works (proves the Paketo workaround held).
- Set `APP_SECURITY_DEV_AUTH_ENABLED=true`, restart, hit `/api/v1/dev/users` — returns 200; the SPA shows the dev user picker even though the bundle was built without `VITE_DEV_MODE` set.

## References

- `frontend/src/app/contexts/AuthContext.tsx` — runtime probe pattern replacing `VITE_DEV_MODE`.
- `specs/learnings/infrastructure-spa-routing.md` — discovery during E2E.
- `specs/learnings/infrastructure-runtime-dev-mode.md` — "build-time vs runtime" lesson.
- `specs/learnings/infrastructure-alb-oidc-auth.md` — Paketo strips static, ALB OIDC, env-var feature flags.
