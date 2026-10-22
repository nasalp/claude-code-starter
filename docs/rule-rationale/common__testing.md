# Rationale — common/testing.md

## Why the mutation-testing PR-owned rule exists

Real incident, 2026-05-14: M5 PR added ~190 LOC of new wrap-footer to 3 auth
controllers totaling ~3100 LOC. Stryker ran on the whole files. 2015 mutants
survived — almost all in legacy controller bodies the PR never touched. A
naive iteration loop would have spent days writing tests for pre-M5 code,
inflating the PR's risk and scope. With blame-aware classification the author
only had to address the ~30 PR-owned survived mutants.

## Why the no-regex-over-source rule exists

Real incident, 2026-05-13: a 4-PR stack added `withSpan` instrumentation
to ~60 controllers in dashboard-v2. The author shipped 4 "wrap-shape"
tests that did `fs.readFileSync(controllerPath)` + regex matching to
assert each file contained the wrap pattern. 391 tests passed. The
adversarial reviewer found that:

1. The tests proved "the wrap pattern appears in source text" — NOT
   "the wrap is reachable at runtime", NOT "calling the exported
   method actually emits a span", NOT "the return value is preserved".
2. Commits `fd11bc748` and `d8dedfb45` later fixed 7 unawaited
   fire-and-forget emits and a missing `await` — exactly the class of
   defect a behavior-preservation test should catch. The regex tests
   passed through these bugs.
3. The `tracer-equivalence` test (an actual behavior test) only
   exercised `() => 42` — never the `fn.apply(this, args)` n-ary
   forwarding that the wrap-all-exports footer uses.

A regex test gives the warm feeling of coverage with none of the proof.

## See also

