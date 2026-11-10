import assert from "node:assert/strict";
import { chmod, mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { readBean, readBoard, readFingerprint } from "./board.ts";
import { BeanId } from "../shared/rpc.ts";
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
  path: "x-1--one.md",
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
  const result = await readBoard(root, null, { beans });
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

test("readBoard marks beans under archive/ as archived, without exposing the path", async () => {
  const root = await project();
  const output = {
    beans: [
      BEAN,
      { ...BEAN, id: "x-2", path: "archive/x-2--two.md", status: "completed" },
      { ...BEAN, id: "x-3", path: "archive-notes--three.md" },
    ],
    blocked: [],
  };
  const beans = await fakeBeans(`echo '${JSON.stringify(output)}'`);
  const result = await readBoard(root, null, { beans });
  assert.ok(result.kind === "project");
  assert.deepEqual(
    result.beans.map((bean) => [bean.id, bean.archived]),
    [
      ["x-1", false],
      ["x-2", true],
      ["x-3", false],
    ],
  );
  assert.ok(result.beans.every((bean) => !("path" in bean)));
});

test("with no project, readBoard and readFingerprint say so without running beans", async () => {
  const dir = await tmp("none");
  const beans = await fakeBeans("exit 99");
  assert.deepEqual(await readBoard(dir, null, { beans }), { kind: "none", directory: dir });
  assert.deepEqual(await readFingerprint(dir), { kind: "none", directory: dir });
});

test("a project without its data directory is an empty board, without running beans", async () => {
  const root = await tmp("no-data");
  await writeFile(path.join(root, ".beans.yml"), "beans:\n  path: .beans\n");
  const beans = await fakeBeans("exit 99");
  const result = await readBoard(root, null, { beans });
  assert.equal(result.kind, "project");
  assert.deepEqual(result.kind === "project" && result.beans, []);
});

test("readBoard without a search runs the plain query and reports no matches", async () => {
  const root = await project();
  const beans = await fakeBeans(`echo '${JSON.stringify({ beans: [BEAN], blocked: [] })}'`);
  for (const search of [null, "", "   "]) {
    const result = await readBoard(root, search, { beans });
    assert.deepEqual(
      result.kind === "project" && [result.matches, result.searchError],
      [null, null],
      JSON.stringify(search),
    );
    const argv = (await readFile(path.join(path.dirname(beans), "argv"), "utf8")).split("\n");
    assert.equal(argv[3], "{}");
    assert.ok(!argv.slice(4).join("\n").includes("matches"));
  }
});

test("readBoard passes a search only as a variable and maps the matches", async () => {
  const root = await project();
  const output = { beans: [BEAN, { ...BEAN, id: "x-2" }], blocked: [], matches: [{ id: "x-2" }] };
  const beans = await fakeBeans(`echo '${JSON.stringify(output)}'`);
  const search = 'log* ") { x } #';
  const result = await readBoard(root, ` ${search} `, { beans });
  assert.ok(result.kind === "project");
  assert.deepEqual([result.matches, result.searchError], [["x-2"], null]);
  assert.deepEqual(
    result.beans.map((bean) => bean.id),
    ["x-1", "x-2"],
  );
  const argv = (await readFile(path.join(path.dirname(beans), "argv"), "utf8")).split("\n");
  // The query spans several lines, so it is everything after the variables.
  const query = argv.slice(4).join("\n");
  assert.equal(argv[3], JSON.stringify({ search }));
  assert.ok(!query.includes("log*"));
  assert.match(query, /matches: beans\(filter: \{ search: \$search \}\)/);
});

test("a searched project without its data directory matches nothing, without running beans", async () => {
  const root = await tmp("no-data");
  await writeFile(path.join(root, ".beans.yml"), "beans:\n  path: .beans\n");
  const result = await readBoard(root, "anything", { beans: await fakeBeans("exit 99") });
  assert.ok(result.kind === "project");
  assert.deepEqual([result.beans, result.matches], [[], []]);
});

test("a search the CLI cannot parse is a search error, not a failure", async () => {
  const root = await project();
  for (const [stderr, reason] of [
    ["Error: graphql: syntax error", "syntax error"],
    ["Error: graphql: parse error: unterminated quote", "parse error: unterminated quote"],
    ["Error: graphql: error parsing regexp: missing closing ]: `[`", "error parsing regexp: missing closing ]: `[`"],
  ]) {
    // Fails only the searched query; the unsearched fallback read succeeds.
    const beans = await fakeBeans(
      `case "$*" in *'$search'*) printf '%s\\nUsage:\\n  beans graphql\\n' '${stderr}' >&2; exit 1;; esac
echo '${JSON.stringify({ beans: [BEAN], blocked: [] })}'`,
    );
    const result = await readBoard(root, "title:", { beans });
    assert.ok(result.kind === "project");
    assert.deepEqual(
      [result.beans.map((bean) => bean.id), result.matches, result.searchError],
      [["x-1"], [], reason],
    );
  }
});

test("a CLI parse error without a search, or any other failure, is still an error", async () => {
  const root = await project();
  const parse = await fakeBeans("echo 'Error: graphql: syntax error' >&2; exit 1");
  await assert.rejects(readBoard(root, null, { beans: parse }), /syntax error/);
  const other = await fakeBeans("echo 'Error: graphql: Expected Name, found <EOF>' >&2; exit 1");
  await assert.rejects(readBoard(root, "one", { beans: other }), /Expected Name/);
});

test("a searched read whose output lacks matches is an error", async () => {
  const root = await project();
  const beans = await fakeBeans(`echo '${JSON.stringify({ beans: [BEAN], blocked: [] })}'`);
  await assert.rejects(readBoard(root, "one", { beans }), /no search matches/);
});

test("an unexpected board shape is an error", async () => {
  const root = await project();
  const beans = await fakeBeans(`echo '{"beans": [{"id": 1}], "blocked": []}'`);
  await assert.rejects(readBoard(root, null, { beans }), /unexpected board shape/);
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

const DETAIL = {
  id: "x-1",
  slug: "one",
  title: "One",
  status: "todo",
  implicitStatus: null,
  type: "task",
  priority: null,
  tags: [],
  body: "# Hi",
  createdAt: "2026-01-01T00:00:00Z",
  updatedAt: "2026-01-02T00:00:00Z",
  parent: { id: "x-0", title: "Epic", status: "todo", type: "epic" },
  blockedBy: [],
  children: [],
};

test("readBean passes the id as a variable and maps the bean", async () => {
  const root = await project();
  const beans = await fakeBeans(`echo '${JSON.stringify({ bean: DETAIL })}'`);
  const result = await readBean(root, "x-1", { beans });
  assert.equal(result.kind, "project");
  assert.deepEqual(result.kind === "project" && result.bean, { ...DETAIL, priority: "normal" });
  const argv = (await readFile(path.join(path.dirname(beans), "argv"), "utf8")).split("\n");
  assert.equal(argv[3], '{"id":"x-1"}');
});

test("readBean is null for an unknown id", async () => {
  const root = await project();
  const beans = await fakeBeans(`echo '{"bean": null}'`);
  const result = await readBean(root, "x-9", { beans });
  assert.deepEqual(result.kind === "project" && result.bean, null);
});

test("readBean of a project without its data directory is null, without running beans", async () => {
  const root = await tmp("no-data");
  await writeFile(path.join(root, ".beans.yml"), "beans:\n  path: .beans\n");
  const result = await readBean(root, "x-1", { beans: await fakeBeans("exit 99") });
  assert.deepEqual(result.kind === "project" && result.bean, null);
});

test("the bean id fence admits prefixed ids and rejects anything else", () => {
  for (const id of ["dotfiles-p38z", "my_app.v2-ab12"]) assert.ok(BeanId.safeParse(id).success, id);
  for (const id of ["", "a b", 'x") { y } #', "a\nb", "../x"]) {
    assert.ok(!BeanId.safeParse(id).success, JSON.stringify(id));
  }
});
