// The Claude Code Stop hook (server/stop-hook.sh) repeats STATUS_ENV and the tool-name
// pattern below; change them together.

export const SET_STATUS_TOOL = "set_status";

/** Set in every interactive agent's env while the plugin is loaded; the Stop hook does nothing without it. */
export const STATUS_ENV = "PASEO_STATUS";

/**
 * Providers name MCP tools differently (Claude: `mcp__paseo__set_status`), so this matches
 * any name that ends in the tool name under Paseo's `paseo` MCP server.
 */
export function isSetStatusToolName(name: string): boolean {
  return /(^|[\W_])paseo(__|[./:])set_status$/.test(name);
}
