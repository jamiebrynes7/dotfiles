import assert from "node:assert/strict";
import { test } from "node:test";
import type { ConfigRead } from "./config.ts";
import type { RemoteList } from "./git.ts";
import { decide, matchKeys, withPluginDir, type Deps, type SessionConfig } from "./resolve.ts";

const repositories = {
  "github.com/acme/web": { pluginDir: "/plugins/acme-web" },
  "github.com/acme/api": { pluginDir: "/plugins/acme-api" },
};
const pluginDirs = Object.values(repositories).map((profile) => profile.pluginDir);

function deps(overrides: Partial<{ config: ConfigRead; remotes: RemoteList; dirs: string[] }>): Deps {
  const {
    config = { kind: "ok", repositories },
    remotes = { kind: "ok", urls: ["git@github.com:acme/web.git"] },
    dirs = pluginDirs,
  } = overrides;
  return {
    readConfig: async () => config,
    listRemoteUrls: async () => remotes,
    isDirectory: async (dir) => dirs.includes(dir),
  };
}

const claude: SessionConfig = { provider: "claude", cwd: "/work/web" };

test("a Claude agent in a declared repository loads its plugin", async () => {
  assert.deepEqual(await decide(claude, deps({})), {
    kind: "load",
    key: "github.com/acme/web",
    pluginDir: "/plugins/acme-web",
    alsoMatched: [],
  });
});

test("a non-Claude agent is unchanged without reading anything", async () => {
  const untouched: Deps = {
    readConfig: () => assert.fail("read config"),
    listRemoteUrls: () => assert.fail("ran git"),
    isDirectory: () => assert.fail("checked a path"),
  };
  assert.deepEqual(await decide({ provider: "codex", cwd: "/work/web" }, untouched), {
    kind: "unchanged",
  });
});

test("outside a repository, or with no matching remote, is silent", async () => {
  assert.deepEqual(await decide(claude, deps({ remotes: { kind: "not-a-repository" } })), {
    kind: "unchanged",
  });
  assert.deepEqual(await decide(claude, deps({ remotes: { kind: "ok", urls: [] } })), {
    kind: "unchanged",
  });
  assert.deepEqual(
    await decide(claude, deps({ remotes: { kind: "ok", urls: ["https://github.com/other/x"] } })),
    { kind: "unchanged" },
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
    { kind: "unchanged" },
  );
});

test("a fork matches through its upstream remote", async () => {
  const remotes: RemoteList = {
    kind: "ok",
    urls: ["git@github.com:me/web.git", "https://github.com/acme/web"],
  };
  const decision = await decide(claude, deps({ remotes }));
  assert.equal(decision.kind === "load" && decision.key, "github.com/acme/web");
});

test("several matching keys: the first in remote order wins, the rest are named", async () => {
  const remotes: RemoteList = {
    kind: "ok",
    urls: ["https://github.com/acme/api", "git@github.com:acme/web.git", "https://github.com/acme/api.git"],
  };
  assert.deepEqual(await decide(claude, deps({ remotes })), {
    kind: "load",
    key: "github.com/acme/api",
    pluginDir: "/plugins/acme-api",
    alsoMatched: ["github.com/acme/web"],
  });
});

test("config and git failures, and a missing plugin folder, skip with a reason", async () => {
  const configError = await decide(
    claude,
    deps({ config: { kind: "error", reason: "config file missing", detail: "/c" } }),
  );
  assert.deepEqual(configError, { kind: "skipped", reason: "config file missing", detail: "/c" });

  const gitError = await decide(
    claude,
    deps({ remotes: { kind: "error", reason: "git rev-parse --git-dir timed out" } }),
  );
  assert.deepEqual(gitError, { kind: "skipped", reason: "git rev-parse --git-dir timed out" });

  const missing = await decide(claude, deps({ dirs: [] }));
  assert.deepEqual(missing, {
    kind: "skipped",
    reason: "plugin folder missing or unreadable for github.com/acme/web",
    detail: "/plugins/acme-web",
  });
});

test("an existing plugin-dir is kept and the skip says so", async () => {
  const config: SessionConfig = {
    ...claude,
    providerOptions: { extraArgs: { "plugin-dir": "/mine" } },
  };
  assert.deepEqual(await decide(config, deps({})), {
    kind: "skipped",
    reason: "plugin-dir already set",
    detail: "/mine",
  });
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

test("withPluginDir keeps every other provider option and extraArg", () => {
  const config = {
    ...claude,
    model: "opus",
    providerOptions: {
      maxThinkingTokens: 100,
      extraArgs: { settings: "/s.json", debug: null },
    },
  };
  assert.deepEqual(withPluginDir(config, "/plugins/acme-web"), {
    ...claude,
    model: "opus",
    providerOptions: {
      maxThinkingTokens: 100,
      extraArgs: { settings: "/s.json", debug: null, "plugin-dir": "/plugins/acme-web" },
    },
  });
  assert.deepEqual(withPluginDir(claude, "/p").providerOptions, { extraArgs: { "plugin-dir": "/p" } });
});

test("a matched repository whose profile has no skills is unchanged", async () => {
  const config: ConfigRead = { kind: "ok", repositories: { "github.com/acme/web": {} } };
  assert.deepEqual(await decide(claude, deps({ config, dirs: [] })), { kind: "unchanged" });
});
