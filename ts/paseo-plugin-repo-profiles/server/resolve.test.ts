import assert from "node:assert/strict";
import { test } from "node:test";
import type { ConfigRead, Repositories } from "./config.ts";
import type { RemoteList } from "./git.ts";
import { decide, matchKeys, withExtraArgs, type Decision, type Deps, type SessionConfig } from "./resolve.ts";

const repositories: Repositories = {
  "github.com/acme/web": { pluginDir: "/plugins/acme-web", settings: "/settings/acme-web.json" },
  "github.com/acme/api": { pluginDir: "/plugins/acme-api" },
};
const pluginDirs = ["/plugins/acme-web", "/plugins/acme-api"];
const settingsFiles = ["/settings/acme-web.json"];

function deps(
  overrides: Partial<{ config: ConfigRead; remotes: RemoteList; dirs: string[]; files: string[] }>,
): Deps {
  const {
    config = { kind: "ok", repositories },
    remotes = { kind: "ok", urls: ["git@github.com:acme/web.git"] },
    dirs = pluginDirs,
    files = settingsFiles,
  } = overrides;
  return {
    readConfig: async () => config,
    listRemoteUrls: async () => remotes,
    isDirectory: async (dir) => dirs.includes(dir),
    isReadableFile: async (file) => files.includes(file),
  };
}

const claude: SessionConfig = { provider: "claude", cwd: "/work/web" };
const unchanged: Decision = { set: {}, loaded: [], problems: [] };
const withArgs = (extraArgs: Record<string, unknown>): SessionConfig => ({
  ...claude,
  providerOptions: { extraArgs },
});

test("a Claude agent in a declared repository gets its skills and settings", async () => {
  assert.deepEqual(await decide(claude, deps({})), {
    key: "github.com/acme/web",
    set: { "plugin-dir": "/plugins/acme-web", settings: "/settings/acme-web.json" },
    loaded: ["skills", "settings"],
    problems: [],
  });
});

test("only the fields a profile declares are set", async () => {
  const config: ConfigRead = {
    kind: "ok",
    repositories: { "github.com/acme/web": { settings: "/settings/acme-web.json" } },
  };
  assert.deepEqual(await decide(claude, deps({ config })), {
    key: "github.com/acme/web",
    set: { settings: "/settings/acme-web.json" },
    loaded: ["settings"],
    problems: [],
  });
  const skillsOnly = deps({ remotes: { kind: "ok", urls: ["https://github.com/acme/api"] } });
  assert.deepEqual((await decide(claude, skillsOnly)).set, { "plugin-dir": "/plugins/acme-api" });
});

test("a non-Claude agent is unchanged without reading anything", async () => {
  const untouched: Deps = {
    readConfig: () => assert.fail("read config"),
    listRemoteUrls: () => assert.fail("ran git"),
    isDirectory: () => assert.fail("checked a path"),
    isReadableFile: () => assert.fail("checked a path"),
  };
  assert.deepEqual(await decide({ provider: "codex", cwd: "/work/web" }, untouched), unchanged);
});

test("outside a repository, or with no matching remote, is silent", async () => {
  assert.deepEqual(await decide(claude, deps({ remotes: { kind: "not-a-repository" } })), unchanged);
  assert.deepEqual(await decide(claude, deps({ remotes: { kind: "ok", urls: [] } })), unchanged);
  assert.deepEqual(
    await decide(claude, deps({ remotes: { kind: "ok", urls: ["https://github.com/other/x"] } })),
    unchanged,
  );
});

test("outside a repository, a broken config is still silent", async () => {
  assert.deepEqual(
    await decide(
      claude,
      deps({
        remotes: { kind: "not-a-repository" },
        config: { kind: "error", reason: "config file missing: /c" },
      }),
    ),
    unchanged,
  );
});

test("a fork matches through its upstream remote", async () => {
  const remotes: RemoteList = {
    kind: "ok",
    urls: ["git@github.com:me/web.git", "https://github.com/acme/web"],
  };
  assert.equal((await decide(claude, deps({ remotes }))).key, "github.com/acme/web");
});

test("several matching keys: the first in remote order wins, the rest are named", async () => {
  const remotes: RemoteList = {
    kind: "ok",
    urls: ["https://github.com/acme/api", "git@github.com:acme/web.git", "https://github.com/acme/api.git"],
  };
  assert.deepEqual(await decide(claude, deps({ remotes })), {
    key: "github.com/acme/api",
    set: { "plugin-dir": "/plugins/acme-api" },
    loaded: ["skills"],
    problems: [
      {
        reason: "remotes also match other declared repositories; only the first one's profile is loaded",
        detail: "github.com/acme/web",
      },
    ],
  });
});

test("config and git failures load nothing, with a reason", async () => {
  assert.deepEqual(
    await decide(claude, deps({ config: { kind: "error", reason: "config file missing", detail: "/c" } })),
    { set: {}, loaded: [], problems: [{ reason: "config file missing", detail: "/c" }] },
  );
  assert.deepEqual(
    await decide(claude, deps({ remotes: { kind: "error", reason: "git rev-parse --git-dir timed out" } })),
    { set: {}, loaded: [], problems: [{ reason: "git rev-parse --git-dir timed out" }] },
  );
});

test("a non-object extraArgs loads nothing, with one problem", async () => {
  assert.deepEqual(await decide({ ...claude, providerOptions: { extraArgs: "x" } }, deps({})), {
    key: "github.com/acme/web",
    set: {},
    loaded: [],
    problems: [{ reason: "providerOptions.extraArgs is not an object" }],
  });
});

// Each field on its own: the other field is applied normally in every case.
const fields = [
  { label: "skills", arg: "plugin-dir", path: "/plugins/acme-web", other: "settings" },
  { label: "settings", arg: "settings", path: "/settings/acme-web.json", other: "plugin-dir" },
] as const;
const otherPath = { "plugin-dir": "/plugins/acme-web", settings: "/settings/acme-web.json" };

for (const field of fields) {
  test(`${field.label}: our own value already set is kept, with no problem`, async () => {
    const decision = await decide(withArgs({ [field.arg]: field.path }), deps({}));
    assert.deepEqual(decision.set, { [field.other]: otherPath[field.other] });
    assert.deepEqual(decision.problems, []);
    assert.ok(decision.loaded.includes(field.label));
  });

  test(`${field.label}: a value set elsewhere is kept, and the other field still applies`, async () => {
    const decision = await decide(withArgs({ [field.arg]: "/mine" }), deps({}));
    assert.deepEqual(decision.set, { [field.other]: otherPath[field.other] });
    assert.deepEqual(decision.problems, [
      { field: field.label, reason: `${field.arg} already set`, detail: "/mine" },
    ]);
    assert.deepEqual(decision.loaded, fields.filter((f) => f !== field).map((f) => f.label));
  });

  test(`${field.label}: a missing target is skipped, and the other field still applies`, async () => {
    const missing = field.label === "skills" ? { dirs: [] } : { files: [] };
    const decision = await decide(claude, deps(missing));
    assert.deepEqual(decision.set, { [field.other]: otherPath[field.other] });
    assert.equal(decision.problems.length, 1);
    assert.equal(decision.problems[0]!.field, field.label);
    assert.match(decision.problems[0]!.reason, /missing or unreadable for github\.com\/acme\/web$/);
    assert.equal(decision.problems[0]!.detail, field.path);
  });
}

test("a re-created agent already carrying its whole profile is unchanged", async () => {
  const carried = withArgs({ "plugin-dir": "/plugins/acme-web", settings: "/settings/acme-web.json" });
  assert.deepEqual(await decide(carried, deps({})), unchanged);
  const alsoMatching: RemoteList = {
    kind: "ok",
    urls: ["git@github.com:acme/web.git", "https://github.com/acme/api"],
  };
  assert.deepEqual(await decide(carried, deps({ remotes: alsoMatching })), unchanged);
});

test("owner and repo match regardless of case", () => {
  assert.deepEqual(
    matchKeys(["git@github.com:Acme/Web.git"], ["github.com/acme/web"]),
    ["github.com/acme/web"],
  );
  assert.deepEqual(
    matchKeys(["git@github.com:acme/web.git"], ["github.com/Acme/Web"]),
    ["github.com/Acme/Web"],
  );
});

test("withExtraArgs keeps every other provider option and extraArg", () => {
  const config = {
    ...claude,
    model: "opus",
    providerOptions: {
      maxThinkingTokens: 100,
      extraArgs: { debug: null },
    },
  };
  assert.deepEqual(withExtraArgs(config, { "plugin-dir": "/p", settings: "/s.json" }), {
    ...claude,
    model: "opus",
    providerOptions: {
      maxThinkingTokens: 100,
      extraArgs: { debug: null, "plugin-dir": "/p", settings: "/s.json" },
    },
  });
  assert.deepEqual(withExtraArgs(claude, { "plugin-dir": "/p" }).providerOptions, {
    extraArgs: { "plugin-dir": "/p" },
  });
});

test("a matched repository whose profile has no fields is unchanged", async () => {
  const config: ConfigRead = { kind: "ok", repositories: { "github.com/acme/web": {} } };
  assert.deepEqual(await decide(claude, deps({ config })), unchanged);
});

test("our own value whose target has gone is reported, not taken as loaded", async () => {
  const carried = withArgs({ "plugin-dir": "/plugins/acme-web", settings: "/settings/acme-web.json" });
  const decision = await decide(carried, deps({ files: [] }));
  assert.deepEqual(decision.set, {});
  assert.deepEqual(decision.loaded, ["skills"]);
  assert.deepEqual(
    decision.problems.map((p) => [p.field, p.detail]),
    [["settings", "/settings/acme-web.json"]],
  );
});

test("multi-match with one field ours and the other skipped reports both", async () => {
  const remotes: RemoteList = {
    kind: "ok",
    urls: ["git@github.com:acme/web.git", "https://github.com/acme/api"],
  };
  const decision = await decide(withArgs({ "plugin-dir": "/plugins/acme-web", settings: "/mine" }), deps({ remotes }));
  assert.deepEqual(decision.set, {});
  assert.deepEqual(decision.loaded, ["skills"]);
  assert.deepEqual(
    decision.problems.map((p) => [p.field, p.detail]),
    [
      [undefined, "github.com/acme/api"],
      ["settings", "/mine"],
    ],
  );
});
