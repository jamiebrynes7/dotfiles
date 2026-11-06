import assert from "node:assert/strict";
import { chmod, mkdir, mkdtemp, rename, rm, utimes, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { dataPath, findProject, fingerprintOf } from "./project.ts";

const tmp = (prefix: string) => mkdtemp(path.join(os.tmpdir(), `beans-${prefix}-`));

async function project(config = "beans:\n  path: .beans\n") {
  const root = await tmp("project");
  await writeFile(path.join(root, ".beans.yml"), config);
  await mkdir(path.join(root, ".beans", "archive"), { recursive: true });
  await writeFile(path.join(root, ".beans", "a.md"), "a");
  return root;
}

test("dataPath reads beans.path, unquoted, defaulting to .beans", () => {
  assert.equal(dataPath("beans:\n    path: tasks\n    prefix: x-\n"), "tasks");
  assert.equal(dataPath('beans:\n  path: "my beans" # quoted\n'), "my beans");
  assert.equal(dataPath("other:\n  path: nope\nbeans:\n  prefix: x\n"), ".beans");
  assert.equal(dataPath(""), ".beans");
});

test("findProject searches upward and resolves the data directory", async () => {
  const root = await project("beans:\n  path: data\n");
  const nested = path.join(root, "a", "b");
  await mkdir(nested, { recursive: true });
  assert.deepEqual(await findProject(nested), {
    config: path.join(root, ".beans.yml"),
    dataDir: path.join(root, "data"),
  });
});

test("findProject is null with no .beans.yml up the tree", async () => {
  // The temp dir's ancestors could hold a .beans.yml only on a very odd machine.
  assert.equal(await findProject(await tmp("none")), null);
});

test("findProject reports an unreadable config instead of searching past it", async () => {
  const root = await tmp("dir-config");
  await mkdir(path.join(root, ".beans.yml"));
  await assert.rejects(findProject(root));
});

test("the fingerprint changes on add, edit, remove and archive, and only then", async () => {
  const root = await project();
  const found = (await findProject(root))!;
  const data = found.dataDir;
  const seen = [await fingerprintOf(found)];
  const step = async (change: () => Promise<void>) => {
    await change();
    const next = await fingerprintOf(found);
    assert.ok(!seen.includes(next), "fingerprint should be new");
    seen.push(next);
  };

  assert.equal(await fingerprintOf(found), seen[0], "stable when nothing changed");
  await step(() => writeFile(path.join(data, "b.md"), "b"));
  await step(() => writeFile(path.join(data, "b.md"), "bigger"));
  // Same size, different mtime: an edit that keeps the length still counts.
  await step(() => utimes(path.join(data, "b.md"), new Date(1000), new Date(1000)));
  await step(() => rename(path.join(data, "a.md"), path.join(data, "archive", "a.md")));
  await step(() => rm(path.join(data, "b.md")));
});

test("an unreadable data directory is an error, not 'none'", async (t) => {
  if (process.getuid?.() === 0) return t.skip("root reads everything");
  const root = await project();
  const found = (await findProject(root))!;
  await chmod(found.dataDir, 0o000);
  t.after(() => chmod(found.dataDir, 0o755));
  await assert.rejects(fingerprintOf(found));
});

test("a missing data directory fingerprints as empty, and its creation is a change", async () => {
  const root = await project("beans:\n  path: missing\n");
  const found = (await findProject(root))!;
  const before = await fingerprintOf(found);
  await mkdir(found.dataDir);
  await writeFile(path.join(found.dataDir, "a.md"), "a");
  assert.notEqual(await fingerprintOf(found), before);
});
