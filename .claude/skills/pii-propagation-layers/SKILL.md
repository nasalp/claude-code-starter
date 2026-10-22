---
name: pii-propagation-layers
description: Five-layer PII propagation discipline — every DB schema change must update production tables, masked PG views, in-place obfuscation, Python pii.py parity, and GDPR erase clauses, with a cross-refer...
origin: ECC
triggers: PIIFIELDS, DOMAINEVENTPIIFIELDS, piidomaineventpayload, obfuscate-in-place, gdpr-erase, masked view, pii.py, datapump, GDPR, payload @>, HMACKEY, masktable
---
# PII Propagation Across Layers

Whenever you touch a database table, you must consider PII implications across five separate layers. Each has its own masking/erasure path and they must stay in sync. Skipping a layer creates a leak path. The datapump branch went through 12+ rounds of adversarial review and surfaced multiple GDPR audit findings — every one of them was a layer that drifted out of sync. This skill is the load-bearing checklist that prevents the next leak.

## When to use

- Adding, renaming, or repurposing any column in production tables.
- Adding a new event emitter in `services/dashboard-v2/src/events/emitters.js` or a new event type that may carry PII.
- Modifying any of: `obfuscate-in-place.sh`, a `*_v_*_masked` view, `pii.py`, or `gdpr-erase-domain-events.sh`.
- Reviewing any datapump-touching PR.

## When NOT to use

- Pure read paths that never touch the datapump or domain events.
- Internal-only computed columns that are never exported to BigQuery and not in any masked view.

## The pattern

Five layers must stay in sync. The flow:

```
Production tables (Users, Reviews, ...)
        |
        +--> *_v_*_masked PG views   --+
        |    (datapump -> BQ)          |
        |                              v
        +--> DomainEvents.payload --> obfuscate-in-place.sh
                                       |
                                       v
                                pii.py PII_FIELDS / DOMAIN_EVENT_PII_FIELDS
                                       |
                                       v
                                 gdpr-erase-domain-events.sh
```

### Layer 1 — production table column type

Ask: is the new value PII? Names, emails, phones, IPs, addresses, raw user input, free-text descriptions and any composite that could re-identify a person all qualify.

### Layer 2 — `_masked` view (`sql/00_pii_masked_views.sql`)

Wrap PII columns in the appropriate `pii_*` function (deterministic HMAC, redaction, or domain-preserving hash). Manually scan the SELECT list — every PII column must be wrapped.

### Layer 3 — `obfuscate-in-place.sh` (`sql/datapump/pg/obfuscated-dump/`)

Add the column to the matching `mask_table` call. The masked view and the in-place script MUST mask the same set of columns, or one of the two paths leaks. Round 12 caught six leak paths where the views passed through raw values that the in-place script masked: `event_url`, `offer_redeem_url`, `offer_terms`, `picture_urls`, `submission_id`, `post_title`.

### Layer 4 — `pii.py` (`sql/datapump/lib/pii.py`)

Add the field to `PII_FIELDS["<TableName>"]` (and to `DOMAIN_EVENT_PII_FIELDS` for events). Python and Postgres paths MUST produce identical hashes; a runtime parity check enforces this. Without parity, the same user's pseudonym differs across exports — making cross-export joins impossible and complicating audits.

### Layer 5 — `gdpr-erase-domain-events.sh`

If the column can identify a user (email, phone, IP, address, name), add a clause that finds rows where this column matches the erase target. Use root-level JSONB containment (`payload @> ...`) so the GIN index is used. Round 5 found a HIGH severity bug where `payload->'recipients' @> ...` bypassed the index, causing hours-long Seq Scans per request. The fix is `payload @> jsonb_build_object('recipients', ...)`.

### Cross-reference map

The cross-reference table in the learning is the audit lookup. A truncated version:

| Production table | Masked view | obfuscate-in-place clause | pii.py |
|---|---|---|---|
| Users | `users_v_company_role_masked` | `mask_table "Users"` | `PII_FIELDS["Users"]` |
| Reviews | `reviews_v_detail_masked` | `mask_table "Reviews"` | `PII_FIELDS["Reviews"]` |
| Posts | `posts_v_summary_masked` | `mask_table "Posts"` | `PII_FIELDS["Posts"]` |
| DomainEvents | `domain_events_v_feed_masked` | per-event-type CASE | `DOMAIN_EVENT_PII_FIELDS` |

When you add a row to the production-table column, you must add a row in every other column.

### DomainEvents PII-bearing event types

Fifteen event types currently carry PII. They must stay synchronized between `pii.py:DOMAIN_EVENT_PII_FIELDS`, the `CASE` branches of `pii_domain_event_payload()` in `sql/00_pii_functions.sql`, the `PII_EVENT_TYPES` shell variable in `obfuscate-in-place.sh`, and `DomainEventRetentionPolicy` seed rows. Adding a new emitter that doesn't appear in `DomainEventRetentionPolicy` is blocked by `scripts/ci/check-event-retention-coverage.js`.

## Common gotchas / variants

- HMAC key handling: validate the key charset against `[A-Za-z0-9+/=_-]` in bash before interpolating into PGOPTIONS. Round 5 caught a PGOPTIONS injection vector when the key was naively quoted.
- `xargs` parallel workers do NOT inherit the parent shell's environment automatically. Round 6 was CRITICAL: workers ran with empty `PII_HMAC_KEY`, so every deterministic pseudonym was wrong. Export every variable the worker uses.
- Treat `xargs` non-zero exit as fatal. Round 11 found a WARN-only handler that hid PII gate refusals from CI.
- A masked view that masks columns already covered transitively via a JOIN against another masked table is not a bug — it's defense-in-depth (round 13's two false positives), but document it inline so reviewers don't waste a round noticing.
- Denormalized children: `PostPictures.url` lives only inside `posts_v_summary.picture_urls`. The masked view masks the array; obfuscate-in-place still masks the underlying column.

## Verification

- `python -m pytest sql/datapump/tests/test_pii.py` — Python unit tests, plus shell-script and migration scans for known footguns.
- `npm test -- tests/sql/domainEventsPiiObfuscation.test.js` (testcontainer) — runs actual SQL and verifies obfuscation.
- `node scripts/ci/check-event-retention-coverage.js` — fails if an emitter event type has no `DomainEventRetentionPolicy` row.
- `npm test -- tests/contracts/domainEventShape.contract.test.js` — snapshot of `{eventType, payloadKeys[]}` for every emitter.
- Diff the SELECT list of every `*_v_*_masked` view against the corresponding `mask_table` block in `obfuscate-in-place.sh`. The columns wrapped in one must match the columns masked in the other.
