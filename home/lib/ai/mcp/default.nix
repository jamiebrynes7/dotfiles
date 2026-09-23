# Shared MCP server option types for AI assistant modules.
# Used by claude-code and cursor modules.
{ lib }:
with lib;
let
  # Fields every assistant's MCP config understands. Assistant-specific fields
  # live in the assistant's own module and are merged in via mkServerType, so
  # an assistant only exposes the options it can actually honour.
  commonServerModule = {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to enable this MCP server";
      };

      # Stdio transport
      command = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Command to start a stdio MCP server";
      };
      args = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Arguments passed to the stdio command";
      };
      env = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Environment variables for the stdio server";
      };

      # Remote transport
      url = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "URL for a remote MCP server";
      };
      headers = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "HTTP headers for the remote server";
      };
    };
  };

  enabledServers = servers: filterAttrs (_: s: s.enable) servers;
in
{
  inherit enabledServers;

  # Build a server submodule type from the common fields plus the given
  # assistant-specific modules.
  mkServerType = extraModules: types.submodule ([ commonServerModule ] ++ extraModules);

  # Convert the common fields of a server to a JSON-compatible attrset,
  # omitting fields that are null or empty.
  mkCommonEntry =
    server:
    if server.command != null then
      {
        inherit (server) command;
      }
      // (optionalAttrs (server.args != [ ]) { inherit (server) args; })
      // (optionalAttrs (server.env != { }) { inherit (server) env; })
    else
      {
        inherit (server) url;
      }
      // (optionalAttrs (server.headers != { }) { inherit (server) headers; });

  # Each enabled server must set exactly one of command or url.
  mkServerAssertions =
    moduleName: servers:
    mapAttrsToList (name: server: {
      assertion = (server.command != null) != (server.url != null);
      message = "${moduleName}: MCP server '${name}' must set exactly one of 'command' (stdio) or 'url' (remote), not both or neither.";
    }) (enabledServers servers);
}
