#!/usr/bin/env bash
#
# scripts/promote-learnings/backfill-topics.sh
#
# Scan every discovered project's spec/learnings/*.md and .claude/rules/*.md
# and add a `topic:` YAML frontmatter line when missing — inferring the topic
# from filename + content keywords against the controlled vocabulary in
# $AI_RULES_REPO/spec/promotion-topics.yaml.
#
# Rationale: /promote-learnings can only converge on topics; an untopiced doc
# is invisible to the pipeline. Convergence is by topic string equality —
# a wrong topic causes false-positive convergence and poisons the pipeline.
# So this script *requires* confidence (multiple signals or strong filename
# match) before tagging. Low-confidence files stay untopiced and are listed
# for human review.
#
# Confidence model
# ----------------
# Each rule has a list of regexes. For each file we count signals:
#   filename_hit  +5    (regex matches the basename — strong intent signal)
#   content_hit   +1    (regex matches first 80 lines of body)
# Threshold to auto-tag: total score >= 5 OR (>=2 distinct content matches).
# The single rule with the highest score wins; ties → no tag (ambiguous).
#
# Per project: stages the changes and commits as:
#   "chore(learnings): backfill topic: frontmatter"
# Does NOT push. The agent invoking /promote-learnings reports the commits
# and lets the human decide.
#
# Usage:
#   PROJECTS_ROOT=... AI_RULES_REPO=... scripts/promote-learnings/backfill-topics.sh
#
# Flags:
#   --dry-run      Print would-tag decisions without writing files.
#   --no-commit    Write files but don't git-commit (leaves dirty tree).
#   --verbose      Show per-rule scores per file (debugging).

set -euo pipefail

DRY_RUN=false
NO_COMMIT=false
VERBOSE=false
RESCAN=false
for arg in "$@"; do
    case "$arg" in
        --dry-run)   DRY_RUN=true ;;
        --no-commit) NO_COMMIT=true ;;
        --verbose)   VERBOSE=true ;;
        # --rescan: re-evaluate files that already have a topic. Strips the
        # existing topic/topics frontmatter key(s) and re-infers from scratch.
        # Use this after vocabulary or heuristic changes to backfill multi-
        # topic secondaries on files tagged by an older single-topic run.
        --rescan)    RESCAN=true ;;
        *) echo "[backfill-topics] ERROR: unknown flag: $arg" >&2; exit 1 ;;
    esac
done

if [[ -z "${AI_RULES_REPO:-}" ]] || [[ -z "${PROJECTS_ROOT:-}" ]]; then
    echo "[backfill-topics] ERROR: AI_RULES_REPO and PROJECTS_ROOT must be set." >&2
    exit 1
fi

# --- topic inference rules --------------------------------------------------
#
# Each line: "<topic>|<regex1>|<regex2>|..." — case-insensitive.
# Place more-specific topics BEFORE more-generic ones in case of identical
# scores; ties otherwise fall through to "no tag".
RULES=(
    # Spring profiles (specific) BEFORE Spring beans (generic)
    "java.spring.profiles|spring profile|@profile|active.*profile|spring\.profiles\.active|no-custom-spring-profiles|custom.*spring.*profile"
    "java.spring.ai|spring ai|spring-ai-bom|spring-ai-starter|spring-ai-openai"
    "java.spring.upgrades|spring boot 4|spring boot.*migrat|boot.*upgrade|spring-boot-4"
    "java.spring.testing|@webmvctest|@datajpatest|@MockitoBean|@SpringBootTest.*WebEnvironment|test slice|spring.*test.*starter"
    "java.spring.beans|@bean|bean configuration|@configuration class|component scan"
    "java.jpa|@entity|hibernate|@onetomany|@manytoone|jpa projection|jparepository"
    "java.observability|micrometer.*observation|@observed|tracer.*test|micrometer.*tracing"

    # Oracle fidelity (specific) BEFORE acceptance (broad) BEFORE flake (generic)
    "testing.oracle-fidelity|drift.detection|fragment.only.assert|presence.only.*check|tests verify.*shape|shape.*not.*semantic|parity oracle.*lax|green.*but.*drift|bats.*green.*drift|bats.*miss"
    "testing.acceptance|bats|\\.bats\\b|cucumber|gherkin|atdd|acceptance suite|acceptance test|parity oracle|porting.*acceptance"
    "testing.contract|pact|spring[- ]cloud[- ]contract|spring-cloud-contract|wiremock.*stub|stub.*runner|stubborn|contract test"
    "testing.mutation|mutation testing|pitest|stryker|mutation kill|mutation coverage"
    "testing.flake|flaky test|flake|warn-and-return|flake.investigation|test.*anti-pattern|anti-pattern.*test"
    "testing.e2e|playwright|cypress|selenium|e2e[ -]test|end[- ]to[- ]end|e2e[ -]infrastructure"
    "testing.parallel|parallel test execution|maven-surefire.*parallel|junit.*parallel|testcontainer.*singleton|shared.*singleton"
    "testing.fixtures|test fixture|testcontainer.*reuse|@testcontainer|@TestPropertySource"
    "testing.unit|property[- ]based|jqwik|fast-check|fc\.string|property test"
    "testing.integration|integration test|@SpringBootTest|@DataJpaTest|integration.*test.*setup"

    "db.migration|flyway|liquibase|sequelize.*migration|database migration|migration.*safety"
    "db.schema|bounded[- ]context view|postgres view|create view|view definition|sql.*view"
    "db.idempotency|idempotency|saveAndFlush|idempotent insert|insert on conflict"
    "db.tenant-isolation|tenant isolation|multi-tenant|tenant.*owner|subdomain.*tenant"
    "db.partitioning|partition.*table|drop.*partition|partition pruning|partitioned"
    "db.replica|read replica|search_path|currentSchema|replica routing"

    "security.pii|\\bpii\\b|gdpr|personal.*data|pii.*propagation|pii scrub|pii.*log"
    "security.secrets|secret rotation|hardcoded secret|secrets.*validator|env var.*secret|startup.*secret"
    "security.auth|jwt verification|oauth|authenticateoidc|alb.*oidc|oidc.*signature|cookie.*startup|auth-cookie"
    "security.authz|@preauthorize|rbac|permission system|fine[- ]grained.*author"
    "security.rate-limit|rate limit|throttle|rate-limit|redis.*mandatory.*rate"
    "security.proxy-headers|x-forwarded-for|trusted proxy|cloudfront header|xff.*spoof"
    "security.audit-log|audit log|audit trail|tamper.*log"

    "infra.gha|github actions|\\.github/workflows|reusable workflow|workflow_call|ci minute|ci.*minute"
    "infra.cdk|aws cdk|cdk\\.json|cdk assertions|stack synth"
    "infra.terraform|terraform"
    "infra.ecs|ecs task|fargate|ecs cdk|container definition|task definition"
    "infra.lambda|aws lambda|lambda function|lambda handler"
    "infra.deploy|codedeploy|deployment pipeline|deploy strategy|appspec\\.yml"
    "infra.observability|opentelemetry|otel.*sdk|prometheus|grafana|metrics export|otlp"
    "infra.health-checks|health.check|liveness.*probe|readiness.*probe"

    "frontend.bundling|vite|webpack|turbopack|bundle.*size"
    "frontend.routing|react.router|next.*route|route rule"
    "frontend.auth|redux.persist|spa.*auth|frontend.*auth.*redux"
    "frontend.state|redux|zustand|state management"
    "frontend.testing|stryker.*vitest|vitest config|frontend.*test.*stub|adversarial.*frontend"
    "frontend.spa|single page|spa packaging|react.*vite|spa.*forwarding"

    "build.maven|maven-jar-plugin|maven assembly|multi-module|maven-compiler|surefire-plugin"
    "build.gradle|build\\.gradle|gradle plugin|version catalog"

    "node.runtime|bun runtime|bun install|node version|nvm"
    "node.deps|peer dependency|package.json.*deps|isolated.*install"
    "node.express|express middleware|express router|express\\.json"
    "node.observability|otel.*node|opentelemetry.*node|node.*tracing"

    "process.ci|push-without-local-test|local.*ci.*parity|pre-push|push.*without.*test"
    "process.review|code review|adversarial review|pr review|wave.*adversarial|adversarial.*summary"
    "process.docs|spec/learnings|how[- ]to.*navigate|intellij.*navigation|behavior catalog"
    "process.spec|spec/features|behaviour spec|atdd|user story|acceptance criteria"
)

# --- inference -------------------------------------------------------------

# --- strong-phrase booster -------------------------------------------------
#
# A list of distinctive content phrases. When matched in the body, the
# associated topic gets +3 (instead of +1) — they are signals so specific
# that one mention strongly indicates the topic, even without a filename
# anchor. This lets a file's *secondary* theme (e.g. "BATS oracle is weak"
# inside a doc whose filename is about CI discipline) earn a secondary tag.
STRONG_PHRASES=(
    "testing.oracle-fidelity|tests verify.*shape"
    "testing.oracle-fidelity|bats.*verify.*script"
    "testing.oracle-fidelity|green.*but.*drift|drift.*pass.*bats"
    "testing.oracle-fidelity|parity oracle"
    "testing.oracle-fidelity|fragment.only.*assert|presence.only.*check"
    "testing.acceptance|bats suite|\\.bats[^a-z]|porting.*acceptance"
    "testing.contract|spring[- ]cloud[- ]contract|wiremock.*stub.*jar"
    "security.pii|pii.*scrub|pii.*propagat"
    "security.auth|alb[- ]oidc|authenticateoidc"
    "db.idempotency|saveandflush.*conflict|insert.*on.*conflict.*do.*nothing"
)

# infer_topics — write best primary + up to 2 secondaries to stdout, one per
# line. Empty stdout means "no confident match — leave untopiced."
#
# Confidence gates:
#   primary    accepted if score >= 5 (filename hit) OR margin >= 2.
#   secondary  any other topic with score >= 4 — must be either filename-
#              anchored or strong-phrase-boosted (single content hit alone
#              scores 1 and is below threshold). Capped at 2 secondaries.
infer_topics() {
    local file="$1"
    local basename body
    basename=$(basename "$file")
    body=$(head -80 "$file" 2>/dev/null || true)

    declare -A scores=()
    local rule topic regex score
    local IFS_BACKUP=$IFS

    # Base scoring from RULES (filename hit +5, content hit +1).
    for rule in "${RULES[@]}"; do
        IFS='|' read -ra parts <<< "$rule"
        topic="${parts[0]}"
        score=0
        for ((i=1; i<${#parts[@]}; i++)); do
            regex="${parts[$i]}"
            if echo "$basename" | grep -qiE "$regex"; then
                score=$((score + 5))
            fi
            if echo "$body" | grep -qiE "$regex"; then
                score=$((score + 1))
            fi
        done
        if [[ "$score" -gt 0 ]]; then
            scores[$topic]=$((${scores[$topic]:-0} + score))
        fi
    done

    # Strong-phrase boost (+3 per hit).
    for rule in "${STRONG_PHRASES[@]}"; do
        IFS='|' read -ra parts <<< "$rule"
        topic="${parts[0]}"
        regex="${parts[1]}"
        if echo "$body" | grep -qiE "$regex"; then
            scores[$topic]=$((${scores[$topic]:-0} + 3))
        fi
    done
    IFS=$IFS_BACKUP

    if [[ "$VERBOSE" == "true" ]]; then
        for topic in "${!scores[@]}"; do
            echo "    [$basename] $topic=${scores[$topic]}" >&2
        done
    fi

    # Pick primary (first rule in declared order — RULES list is specificity-
    # ordered, so this prefers narrower topics on ties).
    local best_topic="" best_score=0 second_score=0
    for rule in "${RULES[@]}"; do
        IFS='|' read -ra parts <<< "$rule"
        topic="${parts[0]}"
        score=${scores[$topic]:-0}
        if [[ "$score" -gt "$best_score" ]]; then
            second_score=$best_score
            best_score=$score
            best_topic=$topic
        fi
    done
    IFS=$IFS_BACKUP

    # Confidence gate for primary.
    local primary=""
    if [[ "$best_score" -ge 5 ]]; then
        primary=$best_topic
    elif [[ "$best_score" -ge 2 && $((best_score - second_score)) -ge 2 ]]; then
        primary=$best_topic
    fi
    [[ -z "$primary" ]] && return 1
    echo "$primary"

    # Pick up to 2 secondaries: any other topic with score >= 4, in
    # specificity (declared) order.
    local secondaries_emitted=0
    for rule in "${RULES[@]}"; do
        IFS='|' read -ra parts <<< "$rule"
        topic="${parts[0]}"
        [[ "$topic" == "$primary" ]] && continue
        score=${scores[$topic]:-0}
        if [[ "$score" -ge 4 ]]; then
            echo "$topic"
            secondaries_emitted=$((secondaries_emitted + 1))
            [[ "$secondaries_emitted" -ge 2 ]] && break
        fi
    done
    IFS=$IFS_BACKUP
    return 0
}

# write_topics: emits `topic: foo` scalar for one topic, `topics:` list for
# 2+. Preserves any existing YAML frontmatter content below the inserted
# key(s). Uses head/tail rather than awk to avoid awk's `-v` multiline
# parsing issue.
write_topics() {
    local file="$1"
    shift
    local topics=("$@")
    local has_frontmatter=false
    head -1 "$file" 2>/dev/null | grep -q '^---$' && has_frontmatter=true

    {
        if [[ "$has_frontmatter" == "true" ]]; then
            head -1 "$file"
        else
            echo "---"
        fi
        if [[ "${#topics[@]}" -eq 1 ]]; then
            echo "topic: ${topics[0]}"
        else
            echo "topics:"
            local t
            for t in "${topics[@]}"; do
                echo "  - $t"
            done
        fi
        if [[ "$has_frontmatter" == "true" ]]; then
            tail -n +2 "$file"
        else
            echo "---"
            echo
            cat "$file"
        fi
    } > "$file.tmp"
    mv "$file.tmp" "$file"
}

# --- per-project loop -------------------------------------------------------

tagged_total=0
untagged_total=0
projects_changed=()

while IFS= read -r project; do
    [[ -z "$project" ]] && continue
    project_tagged=0
    project_untagged_files=()

    shopt -s nullglob
    for f in "$project"/spec/learnings/*.md "$project"/.claude/rules/*.md; do
        base=$(basename "$f")
        [[ "$base" =~ ^(README|_template)\.md$ ]] && continue
        # Already topiced. Unless --rescan, skip. With --rescan, strip the
        # existing topic/topics key(s) in place so infer_topics sees the
        # file as fresh — non-topic frontmatter (category, related_files,
        # last_updated, …) is preserved.
        if head -15 "$f" | grep -qE '^(topic|topics):'; then
            if [[ "$RESCAN" != "true" ]]; then
                continue
            fi
            # Strip `topic: foo` scalar lines AND `topics:` block (the
            # `topics:` line plus any subsequent `  - foo` items until the
            # next non-indented line).
            awk '
                BEGIN { in_topics_list = 0 }
                /^topic:[[:space:]]/ { next }
                /^topics:[[:space:]]*$/ { in_topics_list = 1; next }
                in_topics_list && /^[[:space:]]+-/ { next }
                in_topics_list { in_topics_list = 0 }
                { print }
            ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
        fi
        # infer_topics writes one topic per line; capture into array.
        if mapfile -t topics < <(infer_topics "$f") && [[ "${#topics[@]}" -gt 0 ]]; then
            label=$(IFS=,; echo "${topics[*]}")
            if [[ "$DRY_RUN" == "true" ]]; then
                echo "  would tag $f -> $label"
            else
                write_topics "$f" "${topics[@]}"
                echo "  tagged $f -> $label"
            fi
            project_tagged=$((project_tagged + 1))
            tagged_total=$((tagged_total + 1))
        else
            project_untagged_files+=("$f")
            untagged_total=$((untagged_total + 1))
        fi
    done
    shopt -u nullglob

    if [[ "$project_tagged" -gt 0 ]]; then
        projects_changed+=("$project")
        if [[ "$DRY_RUN" != "true" && "$NO_COMMIT" != "true" ]]; then
            (
                cd "$project"
                git add spec/learnings/*.md .claude/rules/*.md 2>/dev/null || true
                if ! git diff --cached --quiet; then
                    git commit -m "chore(learnings): backfill topic: frontmatter

Auto-tagged $project_tagged learning/rule file(s) with controlled-
vocabulary topics from ai-rules/spec/promotion-topics.yaml so the
/promote-learnings convergence detector can see them.

Inferred by ai-rules/scripts/promote-learnings/backfill-topics.sh
using filename + content keyword scoring (threshold: filename hit
or content-margin >=2). Files left untopiced require human review." \
                        --quiet
                fi
            )
        fi
    fi

    if [[ "${#project_untagged_files[@]}" -gt 0 ]]; then
        echo "  $(basename "$project"): ${#project_untagged_files[@]} file(s) left untopiced (low confidence — needs human review):"
        for f in "${project_untagged_files[@]}"; do
            echo "    - ${f#$project/}"
        done
    fi
done < <("$AI_RULES_REPO/scripts/promote-learnings/discover-projects.sh")

echo
echo "[backfill-topics] Summary: $tagged_total tagged, $untagged_total left untopiced"
if [[ "${#projects_changed[@]}" -gt 0 && "$DRY_RUN" != "true" && "$NO_COMMIT" != "true" ]]; then
    echo "[backfill-topics] Committed in ${#projects_changed[@]} project(s) — NOT pushed."
fi
