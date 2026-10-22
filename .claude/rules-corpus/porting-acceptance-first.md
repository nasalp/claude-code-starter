# Language-port acceptance-first

# Rule

Port service language A → language B (Python→Java, JS→Go, Ruby→Kotlin, etc.):

1. **Write acceptance suite against SOURCE first.** Pin every observable behavior: every input arg, every conditional, every upstream call (verb + path + every query param + every body field), every multi-call sequence, every response field, every metadata key, every error special case, every edge case.
2. **Run suite against SOURCE until 100% green.** Proves suite *actually pins source behavior* — anything missed is invisible, never see divergence later.
3. **Only then port to TARGET.** Target "done" iff passes same suite with identical observable behavior (e.g. semantic JSON equality), no test changes.
4. Acceptance suite **language-agnostic** — call service over wire (HTTP/gRPC/CLI), don't import either codebase. Recorded mock for downstreams (WireMock, VCR, nock = examples; principle = "recorded mock") so source and target see identical upstreams.

**Two contracts to pin separately:**

| Contract | What it covers | Whose contract |
|---|---|---|
| **API parity** | Outbound HTTP requests (verb + path + query + body, exact field names + types + constants + multi-call sequences) | Backend / downstream |
| **Feature parity** | Inbound caller surface (endpoint name + every input arg + response fields + every metadata key + error codes + content format + validation rules) | Caller / consumer |

Suite MUST pin BOTH. "API-parity-only" ships features caller can't reach. "Feature-parity-only" ships requests backend rejects.

**Explicit divergence allowed but MUST be documented.**

Source does something dumb (internal S3 upload inside function that belongs to backend; brute-force pagination probes doubling latency; etc.) → target may skip — but divergence MUST be:

1. Documented in acceptance suite as explicit "intentional drift" comment.
2. Approved by contract owner (backend team for API parity; client team for feature parity).
3. Have follow-up to fix source or shift work to right layer.

Implicit "I just didn't bother" divergence = bug class this rule prevents.

> Rationale (Promotion note / Why / Calibration / Cross-refs / Panel verdicts): `docs/rule-rationale/porting-acceptance-first.md`
