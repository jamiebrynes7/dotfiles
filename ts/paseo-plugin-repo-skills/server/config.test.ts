import assert from "node:assert/strict";
import { mkdtemp, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { configPath, readConfig } from "./config.ts";

async function withFile(contents: string): Promise<string> {
  const dir = await mkdtemp(path.join(os.tmpdir(), "repo-skills-config-"));
  const file = path.join(dir, "config.json");
  await writeFile(file, contents);
  return file;
}

test("configPath follows XDG_CONFIG_HOME, else ~/.config", () => {
  assert.equal(
    configPath({ XDG_CONFIG_HOME: "/x" }, "/home/u"),
    "/x/paseo-repo-skills/config.json",
  );
  assert.equal(configPath({}, "/home/u"), "/home/u/.config/paseo-repo-skills/config.json");
  assert.equal(
    configPath({ XDG_CONFIG_HOME: "" }, "/home/u"),
    "/home/u/.config/paseo-repo-skills/config.json",
  );
});

test("a valid file gives its repositories", async () => {
  const file = await withFile(
    JSON.stringify({ version: 1, repositories: { "github.com/acme/web": "/p/acme-web" } }),
  );
  assert.deepEqual(await readConfig(file), {
    kind: "ok",
    repositories: { "github.com/acme/web": "/p/acme-web" },
  });
});

test("a missing file is an error naming it", async () => {
  assert.deepEqual(await readConfig("/nonexistent/config.json"), {
    kind: "error",
    reason: "config file missing",
    detail: "/nonexistent/config.json",
  });
});

test("invalid JSON is an error", async () => {
  const result = await readConfig(await withFile("{ not json"));
  assert.equal(result.kind, "error");
  assert.match(result.kind === "error" ? result.reason : "", /not valid JSON/);
});

test("a wrong version or shape is an error", async () => {
  for (const contents of [
    { version: 2, repositories: {} },
    { repositories: {} },
    [],
    { version: 1 },
    { version: 1, repositories: { "github.com/a/b": 3 } },
  ]) {
    const result = await readConfig(await withFile(JSON.stringify(contents)));
    assert.equal(result.kind, "error", JSON.stringify(contents));
  }
});
