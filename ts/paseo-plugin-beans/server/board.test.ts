import assert from "node:assert/strict";
import { chmod, mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { readBoard, readFingerprint } from "./board.ts";
import { graphql } from "./cli.ts";

const tmp = (prefix: string) => mkdtemp(path.join(os.tmpdir(), `beans-${prefix}-`));

// A stand-in `beans` that runs `body` as a shell script, with its argv saved
// alongside so a test can check what was passed.
async function fakeBeans(body: string): Promise<string> {
  const dir = await tmp("bin");
  const script = path.join(dir, "beans");
  await writeFile(script, `#!/bin/sh\nprintf '%s\\n' "$@" > "${dir}/argv"\n${body}\n`);
  await chmod(script, 0o755);
  return script;
}

async function project() {
  const root = await tmp("project");
  await writeFile(path.join(root, ".beans.yml"), "beans:\n  path: .beans\n");
  await mkdir(path.join(root, ".beans"));
  return root;
}

const BEAN = {
  id: "x-1",
  slug: "one",
  title: "One",
  status: "todo",
  implicitStatus: null,
  type: "task",
  priority: null,
  parentId: null,
  updatedAt: "2026-01-01T00:00:00Z",
  tags: ["ui"],
};

test("readBoard maps the query, marking blocked beans and defaulting priority", async () => {
  const root = await project();
  const output = { beans: [BEAN, { ...BEAN, id: "x-2", priority: "high" }], blocked: [{ id: "x-2" }] };
  const beans = await fakeBeans(`echo '${JSON.stringify(output)}'`);
  const result = await readBoard(root, { beans });
  assert.equal(result.kind, "project");
  if (result.kind !== "project") return;
  assert.equal(result.fingerprint, ((await readFingerprint(root)) as { fingerprint: string }).fingerprint);
  assert.deepEqual(
    result.beans.map((bean) => [bean.id, bean.priority, bean.blocked]),
    [
      ["x-1", "normal", false],
      ["x-2", "high", true],
    ],
  );
});

test("with no project, readBoard and readFingerprint say so without running beans", async () => {
  const dir = await tmp("none");
  const beans = await fakeBeans("exit 99");
  assert.deepEqual(await readBoard(dir, { beans }), { kind: "none", directory: dir });
  assert.deepEqual(await readFingerprint(dir), { kind: "none", directory: dir });
});

test("a project without its data directory is an empty board, without running beans", async () => {
  const root = await tmp("no-data");
  await writeFile(path.join(root, ".beans.yml"), "beans:\n  path: .beans\n");
  const beans = await fakeBeans("exit 99");
  const result = await readBoard(root, { beans });
  assert.equal(result.kind, "project");
  assert.deepEqual(result.kind === "project" && result.beans, []);
});

test("an unexpected board shape is an error", async () => {
  const root = await project();
  const beans = await fakeBeans(`echo '{"beans": [{"id": 1}], "blocked": []}'`);
  await assert.rejects(readBoard(root, { beans }), /unexpected board shape/);
});

test("graphql runs in cwd with the query and variables as separate argv", async () => {
  const cwd = await tmp("cwd");
  const beans = await fakeBeans(`echo "{\\"cwd\\": \\"$PWD\\"}"`);
  const data = await graphql(cwd, "query Q($id: ID!) { bean(id: $id) { id } }", { id: "a b" }, {
    beans,
  });
  assert.equal(path.basename((data as { cwd: string }).cwd), path.basename(cwd));
  const argv = (await readFile(path.join(path.dirname(beans), "argv"), "utf8")).trimEnd().split("\n");
  assert.deepEqual(argv, [
    "graphql",
    "--json",
    "-v",
    '{"id":"a b"}',
    "query Q($id: ID!) { bean(id: $id) { id } }",
  ]);
});

test("graphql failures carry stderr's tail", async () => {
  const cwd = await tmp("cwd");
  const failing = await fakeBeans("echo 'Error: graphql: bad field' >&2; exit 1");
  await assert.rejects(graphql(cwd, "{}", {}, { beans: failing }), /exited 1.*bad field/);
});

test("graphql rejects non-JSON output", async () => {
  const cwd = await tmp("cwd");
  const beans = await fakeBeans("echo not json");
  await assert.rejects(graphql(cwd, "{}", {}, { beans }), /not JSON: not json/);
});

test("graphql rejects GraphQL errors in otherwise valid output", async () => {
  const cwd = await tmp("cwd");
  const beans = await fakeBeans(`echo '{"data": null, "errors": [{"message": "boom"}]}'`);
  await assert.rejects(graphql(cwd, "{}", {}, { beans }), /query failed: boom/);
});

test("graphql reports a missing beans binary", async () => {
  const cwd = await tmp("cwd");
  await assert.rejects(
    graphql(cwd, "{}", {}, { beans: path.join(cwd, "no-such-beans") }),
    /not on the daemon's PATH/,
  );
});

test("graphql times out a hung CLI", async () => {
  const cwd = await tmp("cwd");
  const beans = await fakeBeans("exec sleep 10");
  await assert.rejects(graphql(cwd, "{}", {}, { beans, timeoutMs: 200 }), /timed out/);
});
