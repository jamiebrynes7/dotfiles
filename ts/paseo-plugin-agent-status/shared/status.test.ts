import assert from "node:assert/strict";
import { test } from "node:test";
import { formatAge } from "./age.ts";
import { linkLabel } from "./link-label.ts";
import { statusInputSchema } from "./status.ts";
import { isSetStatusToolName } from "./tool-contract.ts";

const MINUTE = 60_000;

test("formatAge picks the largest unit", () => {
  assert.equal(formatAge(-5_000), "just now");
  assert.equal(formatAge(59_999), "just now");
  assert.equal(formatAge(12 * MINUTE + 30_000), "12m ago");
  assert.equal(formatAge(3 * 60 * MINUTE), "3h ago");
  assert.equal(formatAge(50 * 60 * MINUTE), "2d ago");
});

test("statusInputSchema enforces the length limits", () => {
  assert.ok(statusInputSchema.safeParse({ summary: "a".repeat(80), waiting_on: "b".repeat(60) }).success);
  assert.ok(!statusInputSchema.safeParse({ summary: "a".repeat(81) }).success);
  assert.ok(!statusInputSchema.safeParse({ summary: "ok", waiting_on: "b".repeat(61) }).success);
  assert.ok(!statusInputSchema.safeParse({ summary: "   " }).success);
});

test("statusInputSchema validates links", () => {
  const parse = (links: unknown) => statusInputSchema.safeParse({ summary: "ok", links });
  const pr = { kind: "pr", url: "https://github.com/o/r/pull/1" };
  assert.deepEqual(parse([{ ...pr, url: `  ${pr.url} ` }]).data?.links, [pr]);
  assert.ok(parse([pr, { kind: "review", url: "http://localhost:19432/" }, { kind: "other", url: "https://x.dev" }]).success);
  assert.ok(!parse([pr, pr, pr, pr]).success);
  assert.ok(!parse([]).success);
  assert.ok(!parse([{ kind: "spec", url: pr.url }]).success);
  assert.ok(!parse([{ kind: "other", url: "javascript:alert(1)" }]).success);
  assert.ok(!parse([{ kind: "other", url: "file:///etc/passwd" }]).success);
  assert.ok(!parse([{ kind: "pr", url: "#1234" }]).success);
  assert.ok(!parse([{ kind: "other", url: `https://example.com/${"a".repeat(500)}` }]).success);
});

test("linkLabel names each kind of link", () => {
  const pr = (url: string) => linkLabel({ kind: "pr", url });
  assert.equal(pr("https://github.com/owner/repo/pull/1234"), "owner/repo#1234");
  assert.equal(pr("https://github.com/owner/repo/pull/1234/"), "owner/repo#1234");
  assert.equal(pr("https://github.com/owner/repo/pull/1234#discussion_r1"), "owner/repo#1234");
  assert.equal(pr("https://github.com/owner/repo/pull/1234/files"), "github.com/owner/repo/pull/1234/files");
  assert.equal(pr("https://gitlab.com/g/p/-/merge_requests/7/?tab=diffs"), "gitlab.com/g/p/-/merge_requests/7");
  assert.equal(linkLabel({ kind: "review", url: "http://localhost:19432/#abc" }), "Review");
  assert.equal(linkLabel({ kind: "other", url: "https://github.com/owner/repo/pull/1" }), "github.com/owner/repo/pull/1");
  assert.equal(linkLabel({ kind: "from-the-future", url: "https://x.dev/a/" }), "x.dev/a");
});

test("isSetStatusToolName matches the tool under Paseo's MCP server only", () => {
  assert.ok(isSetStatusToolName("mcp__paseo__set_status"));
  assert.ok(isSetStatusToolName("paseo.set_status"));
  assert.ok(!isSetStatusToolName("set_status"));
  assert.ok(!isSetStatusToolName("mcp__other__set_status"));
  assert.ok(!isSetStatusToolName("mcp__paseo__set_status_extra"));
});
