import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { chmod, mkdtemp, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { listRemoteUrls } from "./git.ts";

const tmp = (prefix: string) => mkdtemp(path.join(os.tmpdir(), `repo-skills-${prefix}-`));

// Identity and config isolation, so the tests run the same in the Nix sandbox.
function git(cwd: string, ...args: string[]) {
  execFileSync("git", ["-c", "user.name=t", "-c", "user.email=t@t", ...args], {
    cwd,
    env: { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" },
    stdio: "ignore",
  });
}

test("a directory outside any repository is not-a-repository", async () => {
  assert.deepEqual(await listRemoteUrls(await tmp("plain")), { kind: "not-a-repository" });
});

test("a repository without remotes lists none", async () => {
  const repo = await tmp("empty");
  git(repo, "init", "-q");
  assert.deepEqual(await listRemoteUrls(repo), { kind: "ok", urls: [] });
});

test("remotes come back in config order, and a worktree shares them", async () => {
  const repo = await tmp("repo");
  git(repo, "init", "-q");
  git(repo, "remote", "add", "origin", "git@github.com:me/web.git");
  git(repo, "remote", "add", "upstream", "https://github.com/acme/web");
  git(repo, "remote", "add", "alpha", "https://example.com/a/b");
  git(repo, "commit", "-q", "--allow-empty", "-m", "init");
  const worktree = path.join(await tmp("wt"), "wt");
  git(repo, "worktree", "add", "-q", worktree, "-b", "feature");

  const expected = {
    kind: "ok",
    urls: ["git@github.com:me/web.git", "https://github.com/acme/web", "https://example.com/a/b"],
  };
  assert.deepEqual(await listRemoteUrls(repo), expected);
  assert.deepEqual(await listRemoteUrls(worktree), expected);
});

test("a broken worktree link is an error, not a silent non-repository", async () => {
  const dir = await tmp("broken");
  await writeFile(path.join(dir, ".git"), "gitdir: /nonexistent/.git/worktrees/x\n");
  const result = await listRemoteUrls(dir);
  assert.equal(result.kind, "error");
  assert.match(result.kind === "error" ? result.reason : "", /exited 128/);
});

test("a hanging git is cut off by the timeout", async () => {
  const dir = await tmp("hang");
  const fake = path.join(dir, "git");
  await writeFile(fake, "#!/bin/sh\nexec sleep 30\n");
  await chmod(fake, 0o755);

  const started = Date.now();
  const result = await listRemoteUrls(dir, { git: fake, timeoutMs: 200 });
  assert.equal(result.kind, "error");
  assert.match(result.kind === "error" ? result.reason : "", /timed out after 200ms/);
  assert.ok(Date.now() - started < 2_000);
});

test("an aborted signal stops the call", async () => {
  const dir = await tmp("abort");
  const fake = path.join(dir, "git");
  await writeFile(fake, "#!/bin/sh\nexec sleep 30\n");
  await chmod(fake, 0o755);

  const controller = new AbortController();
  setTimeout(() => controller.abort(), 50);
  const result = await listRemoteUrls(dir, { git: fake, signal: controller.signal });
  assert.equal(result.kind, "error");
  assert.match(result.kind === "error" ? result.reason : "", /aborted/);
});

test("a missing git binary is an error", async () => {
  const result = await listRemoteUrls(await tmp("nogit"), { git: "/nonexistent/git" });
  assert.equal(result.kind, "error");
});
