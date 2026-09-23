{ lib }:
with lib;
let
  mcp = import ../../lib/ai/mcp { inherit lib; };

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

  # Cursor-only fields layered on top of the shared MCP server options.
  cursorServerModule = {
    options = {
      envFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to an environment file (stdio servers only)";
      };
      auth = mkOption {
        type = types.nullOr mcpAuthType;
        default = null;
        description = "OAuth configuration for the remote server";
      };
    };
  };

  mcpServerType = mcp.mkServerType [ cursorServerModule ];

  # Convert an auth submodule value to JSON-compatible attrset with the
  # CLIENT_ID / CLIENT_SECRET / scopes keys Cursor expects.
  mkAuth =
    auth:
    {
      CLIENT_ID = auth.clientId;
    }
    // (optionalAttrs (auth.clientSecret != null) {
      CLIENT_SECRET = auth.clientSecret;
    })
    // (optionalAttrs (auth.scopes != [ ]) { scopes = auth.scopes; });

  # Convert a single MCP server definition to its JSON-compatible attrset,
  # omitting fields that are null or empty.
  mkServerEntry =
    _name: server:
    mcp.mkCommonEntry server
    // (
      if server.command != null then
        optionalAttrs (server.envFile != null) { inherit (server) envFile; }
      else
        optionalAttrs (server.auth != null) { auth = mkAuth server.auth; }
    );

  # Filter to enabled servers and build the top-level mcpServers attrset.
  mergeMcpServers = serverDefs: mapAttrs mkServerEntry (mcp.enabledServers serverDefs);

  mkServerAssertions = mcp.mkServerAssertions "cursor";
in
{
  inherit
    mcpAuthType
    mcpServerType
    mergeMcpServers
    mkServerAssertions
    ;
}
