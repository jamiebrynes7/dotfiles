# The pinned beans frontend lockfile was authored under pnpm 9; pnpm 10's
# fetcher (26.05 default) produces a deps store its own build step can't
# consume offline. Pin both fetch and build to pnpm_9 so they agree.
{ lib, stdenv, buildGoModule, fetchFromGitHub, pnpm_9, nodejs }:

let
  data = builtins.fromJSON (builtins.readFile ./data.json);

  src = fetchFromGitHub {
    owner = "hmans";
    repo = "beans";
    rev = data.rev;
    hash = data.hash;
  };

  # pnpm 9 rejects a pnpm-workspace.yaml without a `packages` field; the
  # upstream file only sets onlyBuiltDependencies. Add an empty packages list
  # here too so the fetch and the build (below) see the same workspace config.
  pnpmDeps = pnpm_9.fetchDeps {
    pname = "beans-frontend";
    version = data.version;
    src = "${src}/frontend";
    hash = data.pnpmDepsHash;
    fetcherVersion = 3;
    postPatch = ''
      echo 'packages: []' >> pnpm-workspace.yaml
    '';
  };

  frontend = stdenv.mkDerivation {
    pname = "beans-frontend";
    version = data.version;
    src = "${src}/frontend";

    nativeBuildInputs = [ pnpm_9 nodejs pnpm_9.configHook ];

    inherit pnpmDeps;

    postPatch = ''
      echo 'packages: []' >> pnpm-workspace.yaml
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

  subPackages = [ "cmd/beans" "cmd/beans-serve" ];

  meta = with lib; {
    description = "A CLI-based, flat-file issue tracker for humans and robots";
    homepage = "https://github.com/hmans/beans";
    license = licenses.mit;
  };
}
