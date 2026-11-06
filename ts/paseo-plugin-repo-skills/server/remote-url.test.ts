import assert from "node:assert/strict";
import { test } from "node:test";
import { normaliseRemoteUrl } from "./remote-url.ts";

test("SSH and HTTPS forms normalise to one key", () => {
  for (const url of [
    "git@github.com:acme/web.git",
    "git@github.com:acme/web",
    "ssh://git@github.com/acme/web",
    "ssh://git@github.com:22/acme/web.git",
    "https://github.com/acme/web",
    "https://github.com/acme/web.git",
    "https://github.com/acme/web/",
    "https://github.com/acme/web.git/",
    "https://user:token@github.com:443/acme/web.git",
    "git://github.com/acme/web.git",
  ]) {
    assert.equal(normaliseRemoteUrl(url), "github.com/acme/web", url);
  }
});

test("the host is lowercased and the path keeps its case", () => {
  assert.equal(normaliseRemoteUrl("git@GitHub.COM:Acme/Web.git"), "github.com/Acme/Web");
  assert.equal(normaliseRemoteUrl("https://GITHUB.com/Acme/Web"), "github.com/Acme/Web");
});

test("subgroup paths are kept whole", () => {
  assert.equal(
    normaliseRemoteUrl("git@gitlab.com:group/sub/repo.git"),
    "gitlab.com/group/sub/repo",
  );
});

test("local remotes have no key", () => {
  for (const url of ["/srv/git/web.git", "../web", "./web", "file:///srv/git/web.git", ""]) {
    assert.equal(normaliseRemoteUrl(url), null, url);
  }
});
