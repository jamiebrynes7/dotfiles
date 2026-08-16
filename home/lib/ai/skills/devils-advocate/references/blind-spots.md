# Engineering Blind Spots

Eleven categories engineers consistently miss. Run the list as a checklist: for each, ask the lead question, and use the named misses as the concrete things to go looking for.

## 1. Security — "Can user A access user B's data by manipulating the request?"

Broken object-level authorization (authenticated but not *authorized* for that entity ID) is the top API vulnerability. Also: mass assignment (`{"role": "admin"}` in a profile update), verbose errors leaking stack traces and SQL, sequential IDs that invite enumeration, secrets in log lines, missing rate limits, unvalidated input size/encoding, missing security headers, endpoints triggerable cross-site (CSRF/SSRF), and dependencies with known CVEs.

## 2. Scalability — "What happens at 100x current scale?"

Failures here are nonlinear: 50ms at 1k rows is 30s at 1M. Look for N+1 queries, unbounded `SELECT` with no LIMIT, missing pagination, filter columns with no index (invisible until the table grows), cache stampede on expiry, and nested loops that become quadratic. Ask what fails *first* at 10x traffic, which key or partition is hot, and what it costs.

## 3. Data lifecycle — "If we delete this user, what happens to their data everywhere?"

Creation and reads get attention; retention and deletion don't. Right-to-erasure gaps are the classic: user removed from `users`, still present in `audit_log`, `analytics_events`, `email_log`, exports, and third-party integrations. Also orphaned records, soft-delete applied inconsistently across queries (deleted rows leak into some results), PII captured in structured logs, no retention policy at all, and no clean line between current state and historical snapshot.

## 4. Integration points — "What happens when this dependency is down for an hour?"

Mocked in dev, flaky in prod. Check timeouts (a 30s-or-infinite default blocks threads and cascades), missing circuit breakers, retry safety/idempotency, strict deserialization that breaks on any upstream field change, rate limits, token expiry and refresh failure, and whether there's any fallback or graceful degradation. Webhooks arrive duplicated, out of order, and hours late — never assume once-and-in-order.

## 5. Failure modes — "If step 3 of 5 fails, what state is the system in?"

`catch (e) { log(e) }` is not error handling. Look for partial-operation inconsistency with no compensation (order created, payment never charged), retry storms without exponential backoff and jitter, silent failures where the system looks healthy but produces wrong results, useless error text, poison messages blocking a queue, and dead-letter queues nobody monitors. Ask whether recovery is self-healing or manual.

## 6. Concurrency — "If two users do this at the exact same time, what happens?"

Non-deterministic, so tests pass. Check-then-act without a lock (`if not exists: create`) lets both requests through. Lost updates: two reads of 100, both add 50, both write 150. Counter drift from read-modify-write instead of atomic increment. Double-submit with no idempotency key. Locks held across I/O, deadlock ordering, and connection-pool exhaustion from long transactions.

## 7. Environment gaps — "What's different about production that we're not testing?"

Config values, data volume, network latency and DNS behaviour, service-account permissions, secret management, resource limits, pinned vs. floating dependency versions, feature-flag state. Concretely: timezone set by a cloud default, `/tmp` assumed unlimited but capped at 512MB, TLS only in prod, and missing env vars that dev papers over with defaults — crashing at startup, or worse, silently using the wrong value.

## 8. Observability — "Can the on-call engineer debug this at 3am with what exists?"

Zero user-facing value until it's the only thing that matters. Watch for log-and-pray (logs nobody queries, no alerts, no runbook), no correlation ID to trace a request across services, metric cardinality explosions from user-ID tags, alert fatigue burying real alerts, and technical metrics without business metrics — infrastructure green while orders-per-minute is zero.

## 9. Deployment — "Can we roll this back in 5 minutes without data loss?"

The blind spot is *during*, not before/after. Non-reversible migrations break rollback because old code expects the old column. Also: breaking API changes without versioning (client and server briefly disagree), stale caches serving the old response format, session loss on blue/green switchover, and `ALTER` under load locking a table until everything times out. Ask whether the feature can be turned off without a deploy.

## 10. Multi-tenancy — "Does every query filter by tenant, including this new one?"

Owned by no single feature, touches all of them; each feature is correct in isolation. One missed `tenant_id` is a cross-tenant leak. Also unnamespaced cache keys (`user:123` collides across tenants), global rate limits where one tenant's burst blocks everyone, tenant rules hardcoded in if-statements, and background jobs that leak tenant context from one iteration into the next.

## 11. Edge cases — "What does this look like with zero data? Maximum data? Unicode?"

Empty state (blank screen or "no results" before the user has searched), boundaries (max, min, exactly zero, negative), floats for money (`0.1 + 0.2 !== 0.3` — use integer cents), timezone-naive datetimes and DST transitions that don't exist or happen twice, `Feb 29`, name fields that reject O'Brien or Müller or a 50-character legitimate name, off-by-one pagination duplicating or skipping an item, and uploads with no size cap.
