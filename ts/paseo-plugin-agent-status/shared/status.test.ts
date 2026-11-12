import assert from "node:assert/strict";
import { test } from "node:test";
import { formatAge } from "./age.ts";
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

test("isSetStatusToolName matches the tool under Paseo's MCP server only", () => {
  assert.ok(isSetStatusToolName("mcp__paseo__set_status"));
  assert.ok(isSetStatusToolName("paseo.set_status"));
  assert.ok(!isSetStatusToolName("set_status"));
  assert.ok(!isSetStatusToolName("mcp__other__set_status"));
  assert.ok(!isSetStatusToolName("mcp__paseo__set_status_extra"));
});
