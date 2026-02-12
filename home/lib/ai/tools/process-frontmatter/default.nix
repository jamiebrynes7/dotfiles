{ python3 }:
let
  python = python3.withPackages (ps: [ ps.pyyaml ]);
in
python.pkgs.buildPythonApplication {
  pname = "process-frontmatter";
  version = "0.1.0";
  format = "other";

  src = ./.;

  propagatedBuildInputs = [ python.pkgs.pyyaml ];

  installPhase = ''
    mkdir -p $out/bin
    cp process-frontmatter.py $out/bin/process-frontmatter
    chmod +x $out/bin/process-frontmatter
  '';
}
