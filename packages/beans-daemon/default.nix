{
  lib,
  craneLib,
  commonArgs,
  cargoArtifacts,
}:
craneLib.buildPackage (
  commonArgs
  // {
    pname = "beans-daemon";
    version = "0.1.0";
    inherit cargoArtifacts;
    # Builds all workspace members: `beansd` (daemon binary, mainProgram) and
    # `beansctl` (control CLI used by the chpwd hook and direct invocation).
    # Both binaries are installed to $out/bin. `--workspace` comes from
    # `commonArgs.cargoExtraArgs`.
    #
    # Tests run as a dedicated `beans-daemon-test` flake check, so skip them in
    # the package build to keep it lean (deps are already cached via
    # cargoArtifacts).
    doCheck = false;
    meta = with lib; {
      description = "Background daemon (beansd) and control CLI (beansctl) for the beans issue tracker";
      mainProgram = "beansd";
      license = licenses.mit;
    };
  }
)
