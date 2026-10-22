# Tag Existing Global Rules

Adds frontmatter to rule files in ~/.claude/rules/ that do not have it yet.
Skips files already tagged. Processes in batches of 5 for user review.

## Find untagged files

Run:
  for f in ~/.claude/rules/*.md; do
    [ -f "$f" ] || continue
    head -1 "$f" | grep -q '^---' \
      && echo "TAGGED   $(basename $f)" \
      || echo "UNTAGGED $(basename $f)"
  done

## For each untagged file

Read the full content. Infer:

  tags:        technology and framework keywords present in the content
               common values: spring-web spring-kafka spring-batch spring-data-jpa
               testcontainers micrometer observability kafka avro redis docker
               kubernetes maven gradle java kotlin typescript python go rust
               swift rest http grpc sql jpa hibernate security oauth2 jwt
               reactor webflux openapi logging tracing metrics tdd testing ci git
               node react nextjs express django flask fastapi rails phoenix

  applies-to:  feature types this rule governs
               common values: rest-endpoint event-listener batch-job cli-command
               scheduled-task repository service controller any

  universal:   true only if the rule applies to ALL features regardless of tech
               default is false — use true only for tdd error-handling git hygiene

Process in batches of 5. Show proposed frontmatter for each file:

  === ~/.claude/rules/spring-web.md ===
  Current first line: [first line of file]
  Proposed:
  ---
  tags: [spring-web, spring-mvc, rest, http]
  applies-to: [rest-endpoint, controller]
  universal: false
  ---

Ask: Correct? Type yes to write all, skip N to skip file N, or correct any tags.

## Write confirmed frontmatter

For each confirmed file: prepend the frontmatter block, preserve body exactly.

## Summary

  Tagged:  [n] files
  Skipped: [n] files

  Run /user:refresh-project in any open project to pick up the tagged rules.
