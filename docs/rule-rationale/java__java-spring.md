# Rationale — java/java-spring.md

## Why: spring-boot-maven-plugin placement

On the parent, every module — including library modules consumed elsewhere — runs `repackage` during `package`. The fat-JAR rewrites `MANIFEST.MF` + JAR layout, **breaking the library JAR for any downstream consumer.** Parent JAR ends up with `BOOT-INF/` entries; library JARs lose normal classpath layout. Build time balloons because every module assembles a fat JAR.
