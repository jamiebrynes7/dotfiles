import assert from "node:assert/strict";
import { test } from "node:test";
import type { ConfigRead } from "./config.ts";
import type { RemoteList } from "./git.ts";
import { registerHooks } from "./hooks.ts";
import { TOKEN_ENV, createWarningLedger } from "./warnings.ts";

type Handler = (payload: any, context: any) => Promise<any>;

const repositories = {
  "github.com/acme/web": { pluginDir: "/plugins/acme-web" },
  "github.com/acme/api": { pluginDir: "/plugins/acme-api" },
};
const pluginDirs = Object.values(repositories).map((profile) => profile.pluginDir);

interface Setup {
  config?: ConfigRead;
  readConfig?: () => Promise<ConfigRead>;
  remotes?: RemoteList;
  dirs?: string[];
  files?: string[];
  append?: (agentId: string, item: unknown) => Promise<unknown>;
}

// Drives the three hooks the way the daemon's createAgent does: create.before, then
// open.before with the agent id and the env create.before returned, then create.after.
function harness(setup: Setup = {}) {
  // Read on every creation, so a test can change the setup between two of them.
  const current = () => ({
    config: setup.config ?? ({ kind: "ok", repositories } as ConfigRead),
    remotes: setup.remotes ?? ({ kind: "ok", urls: ["git@github.com:acme/web.git"] } as RemoteList),
    dirs: setup.dirs ?? pluginDirs,
    files: setup.files ?? [],
  });
  const handlers = new Map<string, Handler>();
  const rows: { agentId: string; item: any }[] = [];
  const append = setup.append ?? (async (agentId, item) => rows.push({ agentId, item }));
  const server = {
    addHook(name: string, handler: Handler) {
      handlers.set(name, handler);
      return () => handlers.delete(name);
    },
  };
  const remove = registerHooks(server as never, {
    ledger: createWarningLedger(),
    resolve: () => ({
      readConfig: setup.readConfig ?? (async () => current().config),
      listRemoteUrls: async () => current().remotes,
      isDirectory: async (dir) => current().dirs.includes(dir),
      isReadableFile: async (file) => current().files.includes(file),
    }),
  });
  const context = {
    signal: new AbortController().signal,
    paseo: { agents: { ref: (id: string) => ({ timeline: { append: (item: unknown) => append(id, item) } }) } },
  };
  const hook = (name: string) => handlers.get(name)!;

  async function createAgent(
    agentId: string,
    request: { config: Record<string, unknown>; env?: Record<string, string> },
    { fail = false } = {},
  ) {
    const created = (await hook("agent.create.before")({ request }, context)) ?? request;
    if (fail) return { created, launched: undefined };
    const open = {
      agentId,
      cwd: request.config.cwd,
      provider: request.config.provider,
      reason: "create",
      env: { ...created.env },
    };
    const opened = (await hook("agent.open.before")({ request: open }, context)) ?? open;
    await hook("agent.create.after")({ agent: { id: agentId, cwd: open.cwd } }, context);
    return { created, launched: opened };
  }

  return { createAgent, rows, hook, context };
}

const claude = { provider: "claude", cwd: "/work/web" };

test("each warning case posts one row naming the reason, to that agent", async () => {
  const cases: [string, Setup, RegExp][] = [
    ["config missing", { config: { kind: "error", reason: "config file missing: /c" } }, /config file missing/],
    ["config invalid", { config: { kind: "error", reason: "config file is not valid JSON: /c" } }, /not valid JSON/],
    ["git failing", { remotes: { kind: "error", reason: "git rev-parse exited 128" } }, /exited 128/],
    ["git timing out", { remotes: { kind: "error", reason: "git config timed out after 5000ms" } }, /timed out/],
    ["plugin folder missing", { dirs: [] }, /plugin folder missing or unreadable for github\.com\/acme\/web$/],
  ];
  for (const [name, setup, reason] of cases) {
    const h = harness(setup);
    const { launched } = await h.createAgent("agent-1", { config: claude });
    assert.equal(h.rows.length, 1, name);
    assert.equal(h.rows[0]!.agentId, "agent-1", name);
    assert.equal(h.rows[0]!.item.data.problems.length, 1, name);
    assert.match(h.rows[0]!.item.data.problems[0].reason, reason, name);
    assert.deepEqual(h.rows[0]!.item.data.loaded, [], name);
    assert.equal(h.rows[0]!.item.version, 2, name);
    assert.equal(h.rows[0]!.item.kind, "repo-profiles-warning", name);
    assert.equal(launched.env[TOKEN_ENV], undefined, `${name}: token reaches the agent`);
  }
});

test("plugin-dir already set: kept, and a row says so", async () => {
  const h = harness();
  const config = { ...claude, providerOptions: { extraArgs: { "plugin-dir": "/mine" } } };
  const { created } = await h.createAgent("agent-1", { config });
  assert.deepEqual(created.config, config);
  assert.deepEqual(h.rows[0]!.item.data, {
    problems: [{ field: "skills", reason: "plugin-dir already set", detail: "/mine" }],
    key: "github.com/acme/web",
    loaded: [],
  });
});

test("several matching keys: the first loads and the row names the others", async () => {
  const h = harness({
    remotes: { kind: "ok", urls: ["https://github.com/acme/api", "git@github.com:acme/web.git"] },
  });
  const { created } = await h.createAgent("agent-1", { config: claude });
  assert.equal(created.config.providerOptions.extraArgs["plugin-dir"], "/plugins/acme-api");
  assert.equal(h.rows[0]!.item.data.key, "github.com/acme/api");
  assert.deepEqual(h.rows[0]!.item.data.loaded, ["skills"]);
  assert.equal(h.rows[0]!.item.data.problems[0].detail, "github.com/acme/web");
});

test("silent cases and a clean load add no row and no token", async () => {
  const cases: [string, Record<string, unknown>, Setup][] = [
    ["non-Claude agent", { provider: "codex", cwd: "/work/web" }, {}],
    ["not a git repository", claude, { remotes: { kind: "not-a-repository" } }],
    ["no matching remote", claude, { remotes: { kind: "ok", urls: ["https://github.com/other/x"] } }],
    ["successful load", claude, {}],
  ];
  for (const [name, config, setup] of cases) {
    const h = harness(setup);
    const { created, launched } = await h.createAgent("agent-1", { config, env: { A: "1" } });
    assert.deepEqual(h.rows, [], name);
    assert.deepEqual(created.env, { A: "1" }, name);
    assert.deepEqual(launched.env, { A: "1" }, name);
  }
});

test("a successful load keeps env and other request keys", async () => {
  const h = harness();
  const { created } = await h.createAgent("agent-1", {
    config: { ...claude, model: "opus" },
    env: { A: "1" },
  });
  assert.equal(created.config.model, "opus");
  assert.equal(created.config.providerOptions.extraArgs["plugin-dir"], "/plugins/acme-web");
  assert.deepEqual(created.env, { A: "1" });
});

test("a warning from a failed creation does not reach the next agent in the directory", async () => {
  const setup: Setup = { dirs: [] };
  const h = harness(setup);
  await h.createAgent("agent-1", { config: claude }, { fail: true });
  setup.dirs = undefined;
  await h.createAgent("agent-2", { config: claude });
  assert.deepEqual(h.rows, []);
});

test("a re-created agent carrying our own plugin-dir adds no row", async () => {
  const h = harness();
  const { created } = await h.createAgent("agent-1", { config: claude });
  // Paseo re-creates a stored agent with no provider session from its saved config.
  const { created: again } = await h.createAgent("agent-1", { config: created.config });
  assert.deepEqual(again.config, created.config);
  assert.deepEqual(h.rows, []);
});

test("a creation that fails after claiming does not post on a retry with the same id", async () => {
  const setup: Setup = { dirs: [] };
  const h = harness(setup);
  const before = h.hook("agent.create.before");
  const open = h.hook("agent.open.before");
  const created = await before({ request: { config: claude } }, h.context);
  await open(
    { request: { agentId: "agent-1", cwd: claude.cwd, reason: "create", env: created.env } },
    h.context,
  );
  // createSession throws here, so create.after never runs. The retry loads cleanly.
  setup.dirs = undefined;
  await h.createAgent("agent-1", { config: claude });
  assert.deepEqual(h.rows, []);
});

test("a resumed agent has the saved token stripped and posts nothing", async () => {
  const h = harness();
  const open = { agentId: "agent-1", cwd: "/work/web", reason: "resume", env: { [TOKEN_ENV]: "t", A: "1" } };
  const opened = await h.hook("agent.open.before")({ request: open }, h.context);
  assert.deepEqual(opened.env, { A: "1" });
  await h.hook("agent.create.after")({ agent: { id: "agent-1", cwd: "/work/web" } }, h.context);
  assert.deepEqual(h.rows, []);
});

test("a failing append is logged, not thrown", async () => {
  const h = harness({ dirs: [], append: async () => Promise.reject(new Error("agent gone")) });
  await h.createAgent("agent-1", { config: claude });
});

test("an unexpected throw leaves the config unchanged and still posts a row", async () => {
  const h = harness({
    readConfig: async () => {
      throw new Error("boom");
    },
  });
  const { created } = await h.createAgent("agent-1", { config: claude });
  assert.deepEqual(created.config, claude);
  assert.match(h.rows[0]!.item.data.problems[0].reason, /boom/);
});

// A profile with skills and settings, for the cases where both fields are in play.
const both: ConfigRead = {
  kind: "ok",
  repositories: {
    "github.com/acme/web": { pluginDir: "/plugins/acme-web", settings: "/settings/acme-web.json" },
    "github.com/acme/api": { pluginDir: "/plugins/acme-api" },
  },
};
const settingsFiles = ["/settings/acme-web.json"];

test("skills and settings both load, with no row", async () => {
  const h = harness({ config: both, files: settingsFiles });
  const { created } = await h.createAgent("agent-1", { config: claude });
  assert.deepEqual(created.config.providerOptions.extraArgs, {
    "plugin-dir": "/plugins/acme-web",
    settings: "/settings/acme-web.json",
  });
  assert.deepEqual(h.rows, []);
});

test("one field skipped while the other applies: one row lists the skip and what loaded", async () => {
  const h = harness({ config: both, files: [] });
  const { created } = await h.createAgent("agent-1", { config: claude });
  assert.deepEqual(created.config.providerOptions.extraArgs, { "plugin-dir": "/plugins/acme-web" });
  assert.equal(h.rows.length, 1);
  assert.deepEqual(h.rows[0]!.item.data, {
    problems: [
      {
        field: "settings",
        reason: "settings file missing or unreadable for github.com/acme/web",
        detail: "/settings/acme-web.json",
      },
    ],
    key: "github.com/acme/web",
    loaded: ["skills"],
  });
});

test("several problems in one creation share one row", async () => {
  const h = harness({
    config: both,
    files: settingsFiles,
    remotes: { kind: "ok", urls: ["git@github.com:acme/web.git", "https://github.com/acme/api"] },
  });
  const config = { ...claude, providerOptions: { extraArgs: { settings: "/mine.json" } } };
  const { created } = await h.createAgent("agent-1", { config });
  assert.deepEqual(created.config.providerOptions.extraArgs, {
    settings: "/mine.json",
    "plugin-dir": "/plugins/acme-web",
  });
  assert.equal(h.rows.length, 1);
  const { problems, loaded } = h.rows[0]!.item.data;
  assert.deepEqual(loaded, ["skills"]);
  assert.deepEqual(
    problems.map((p: { field?: string; detail?: string }) => [p.field, p.detail]),
    [
      [undefined, "github.com/acme/api"],
      ["settings", "/mine.json"],
    ],
  );
});
