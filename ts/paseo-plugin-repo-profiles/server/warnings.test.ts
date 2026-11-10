import assert from "node:assert/strict";
import { test } from "node:test";
import { TOKEN_ENV, WARNING_TTL_MS, createWarningLedger, withoutToken } from "./warnings.ts";

test("a recorded warning reaches the agent that claimed its token", () => {
  const ledger = createWarningLedger();
  const token = ledger.record({ reason: "config file missing: /c" });
  ledger.claim(token, "agent-1");
  assert.deepEqual(ledger.take("agent-1"), { reason: "config file missing: /c" });
  assert.equal(ledger.take("agent-1"), undefined, "posted once");
});

test("a failed creation's warning never reaches the next agent in the directory", () => {
  const ledger = createWarningLedger();
  ledger.record({ reason: "from the failed creation" });
  // The retry succeeds silently: no token, so nothing is claimed for it.
  assert.equal(ledger.take("agent-2"), undefined);
});

test("unclaimed and untaken entries expire", () => {
  let clock = 0;
  const ledger = createWarningLedger(() => clock);
  const stale = ledger.record({ reason: "stale" });
  const claimed = ledger.record({ reason: "claimed" });
  ledger.claim(claimed, "agent-1");
  clock = WARNING_TTL_MS + 1;
  ledger.claim(stale, "agent-2");
  assert.equal(ledger.take("agent-2"), undefined);
  assert.equal(ledger.take("agent-1"), undefined);
});

test("an unknown token claims nothing", () => {
  const ledger = createWarningLedger();
  ledger.claim("nope", "agent-1");
  assert.equal(ledger.take("agent-1"), undefined);
});

test("withoutToken drops only the token", () => {
  assert.deepEqual(withoutToken({ [TOKEN_ENV]: "t", PATH: "/bin" }), { PATH: "/bin" });
  assert.deepEqual(withoutToken({ PATH: "/bin" }), { PATH: "/bin" });
});
