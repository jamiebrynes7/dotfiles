{
  lib,
  stdenv,
  buildGoModule,
  fetchFromGitHub,
  fetchurl,
  pnpm_11,
  fetchPnpmDeps,
  pnpmConfigHook,
  nodejs,
}:

let
  data = builtins.fromJSON (builtins.readFile ./data.json);

  # pnpm 10/11's fetcher SIGKILLs during `pnpm install` on aarch64-darwin
  # (nixpkgs#525627). Root cause: on macOS arm64, pnpm's Worker threads default
  # to trackUnmanagedFds, and its graceful-fs EAGAIN retry loop churns fds that
  # libuv recycles for internal pipes; Worker teardown then closes libuv's fds
  # and crashes as SIGKILL. Patch the WorkerPool to disable trackUnmanagedFds.
  # See nixpkgs#525627 comment 4635647418 and nodejs/node@7603c7e50c.
  pnpm = pnpm_11.overrideAttrs (_: {
    version = "11.5.2";
    src = fetchurl {
      url = "https://registry.npmjs.org/pnpm/-/pnpm-11.5.2.tgz";
      hash = "sha256-dJ3FT709zenkFLquMsF3yoR3DT/NaciBbVea3D5qLJk=";
    };
    postPatch = ''
      substituteInPlace dist/pnpm.mjs \
        --replace-fail \
          'resourceLimits: this._workerResourceLimits' \
          'resourceLimits: this._workerResourceLimits, trackUnmanagedFds: false'
    '';
  });

  src = fetchFromGitHub {
    owner = "hmans";
    repo = "beans";
    rev = data.rev;
    hash = data.hash;
  };

  # Use the top-level fetchPnpmDeps / pnpmConfigHook with our patched pnpm
  # passed explicitly. The pnpm.fetchDeps / pnpm.configHook passthru attrs
  # ignore overrideAttrs — they hard-reference buildPackages.pnpm_11 — so the
  # trackUnmanagedFds patch above would otherwise never reach the fetch/build.
  pnpmDeps = fetchPnpmDeps {
    pname = "beans-frontend";
    version = data.version;
    src = "${src}/frontend";
    hash = data.pnpmDepsHash;
    fetcherVersion = 4;
    inherit pnpm;
  };

  patchedPnpmConfigHook = pnpmConfigHook.overrideAttrs (prev: {
    propagatedBuildInputs = prev.propagatedBuildInputs or [ ] ++ [ pnpm ];
  });

  frontend = stdenv.mkDerivation {
    pname = "beans-frontend";
    version = data.version;
    src = "${src}/frontend";

    nativeBuildInputs = [
      pnpm
      nodejs
      patchedPnpmConfigHook
    ];

    inherit pnpmDeps;

    # The same nixpkgs#525627 crash as the pnpm patch above, in a worker that
    # patch cannot reach: SvelteKit runs post-build analysis and prerendering in
    # a `worker_threads` Worker (`forked()` in src/utils/fork.js), and its
    # teardown intermittently aborts the build on aarch64-darwin after the site
    # is already written. `--replace-fail` so an upstream rewrite of `forked()`
    # fails the build rather than silently dropping the fix.
    preBuild = ''
      substituteInPlace node_modules/@sveltejs/kit/src/utils/fork.js \
        --replace-fail \
          'const worker = new Worker(fileURLToPath(module), {' \
          'const worker = new Worker(fileURLToPath(module), { trackUnmanagedFds: false,'
    '';

    buildPhase = ''
      runHook preBuild
      pnpm build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r build/. $out/
      runHook postInstall
    '';
  };
in
buildGoModule {
  pname = "beans";
  version = data.version;

  inherit src;

  vendorHash = data.vendorHash;

  preBuild = ''
    rm -rf internal/web/dist
    mkdir -p internal/web/dist
    cp -r ${frontend}/. internal/web/dist/
  '';

  subPackages = [
    "cmd/beans"
    "cmd/beans-serve"
  ];

  meta = with lib; {
    description = "A CLI-based, flat-file issue tracker for humans and robots";
    homepage = "https://github.com/hmans/beans";
    license = licenses.mit;
  };
}
