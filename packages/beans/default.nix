{ lib, stdenv, buildGoModule, fetchFromGitHub, fetchPnpmDeps, pnpm_10, nodejs, pnpmConfigHook }:

let
  data = builtins.fromJSON (builtins.readFile ./data.json);

  src = fetchFromGitHub {
    owner = "hmans";
    repo = "beans";
    rev = data.rev;
    hash = data.hash;
  };

  pnpmDeps = fetchPnpmDeps {
    pname = "beans-frontend";
    version = data.version;
    src = "${src}/frontend";
    hash = data.pnpmDepsHash;
    fetcherVersion = 3;
  };

  frontend = stdenv.mkDerivation {
    pname = "beans-frontend";
    version = data.version;
    src = "${src}/frontend";

    nativeBuildInputs = [ pnpm_10 nodejs pnpmConfigHook ];

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
