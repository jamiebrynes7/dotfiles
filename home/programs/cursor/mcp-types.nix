{ lib }:
with lib;
let
  mcpAuthType = types.submodule {
    options = {
      clientId = mkOption {
        type = types.str;
        description = "OAuth 2.0 Client ID from the MCP provider";
      };
      clientSecret = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "OAuth 2.0 Client Secret (for confidential clients)";
      };
      scopes = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "OAuth scopes to request";
      };
    };
  };

  mcpServerType = types.submodule {
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
      envFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to an environment file (stdio servers only)";
      };

      # Remote transport (SSE / Streamable HTTP)
      url = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "URL for a remote (SSE/HTTP) MCP server";
      };
      headers = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "HTTP headers for the remote server";
      };
      auth = mkOption {
        type = types.nullOr mcpAuthType;
        default = null;
        description = "OAuth configuration for the remote server";
      };
    };
  };

  # Convert an auth submodule value to JSON-compatible attrset with the
  # CLIENT_ID / CLIENT_SECRET / scopes keys Cursor expects.
  mkAuth = auth:
    { CLIENT_ID = auth.clientId; }
    // (optionalAttrs (auth.clientSecret != null) {
      CLIENT_SECRET = auth.clientSecret;
    })
    // (optionalAttrs (auth.scopes != [ ]) { scopes = auth.scopes; });

  # Convert a single MCP server definition to its JSON-compatible attrset,
  # omitting fields that are null or empty.
  mkServerEntry = _name: server:
    if server.command != null then
      { inherit (server) command; }
      // (optionalAttrs (server.args != [ ]) { inherit (server) args; })
      // (optionalAttrs (server.env != { }) { inherit (server) env; })
      // (optionalAttrs (server.envFile != null) { inherit (server) envFile; })
    else
      { inherit (server) url; }
      // (optionalAttrs (server.headers != { }) { inherit (server) headers; })
      // (optionalAttrs (server.auth != null) { auth = mkAuth server.auth; });

  # Filter to enabled servers and build the top-level mcpServers attrset.
  mergeMcpServers = serverDefs:
    let enabledServers = filterAttrs (_: s: s.enable) serverDefs;
    in mapAttrs mkServerEntry enabledServers;

in { inherit mcpAuthType mcpServerType mergeMcpServers; }
