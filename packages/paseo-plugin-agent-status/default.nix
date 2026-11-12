{
  buildPaseoPlugin,
  writeShellApplication,
  jq,
}:
let
  plugin = buildPaseoPlugin {
    pname = "paseo-plugin-agent-status";
    src = ../../ts/paseo-plugin-agent-status;
  };
in
plugin.overrideAttrs (old: {
  # The Claude Code Stop hook that makes agents keep their status current. Claude Code
  # runs it, not the daemon; home/programs/paseo.nix registers it with the plugin.
  passthru = (old.passthru or { }) // {
    stopHook = writeShellApplication {
      name = "paseo-agent-status-stop-hook";
      runtimeInputs = [ jq ];
      text = builtins.readFile ../../ts/paseo-plugin-agent-status/server/stop-hook.sh;
    };
  };
})
