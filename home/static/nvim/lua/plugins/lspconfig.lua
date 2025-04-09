local lsp = require("lspconfig")

local utils = require("utils")
utils.set_key("n", "gD", vim.lsp.buf.declaration)
utils.set_key("n", "gd", vim.lsp.buf.definition)
utils.set_key("n", "K", vim.lsp.buf.hover)
utils.set_key("n", "gi", vim.lsp.buf.implementation)
utils.set_key("n", "ga", vim.lsp.buf.code_action)
utils.set_key("n", "gr", vim.lsp.buf.references)

-- Setup LSP servers
lsp.ts_ls.setup({
	capabilities = require("cmp_nvim_lsp").default_capabilities(),
})
lsp.svelte.setup({})
lsp.gopls.setup({})
lsp.nil_ls.setup({})
lsp.rust_analyzer.setup({})
lsp.lua_ls.setup({
	on_init = function(client)
		-- Assume that if there is no config file, we are editing Neovim config.
		local path = client.workspace_folders[1].name
		if not vim.loop.fs_stat(path .. "/.luarc.json") and not vim.loop.fs_stat(path .. "/.luarc.jsonc") then
			client.config.settings = vim.tbl_deep_extend("force", client.config.settings, {
				Lua = {
					runtime = {
						version = "LuaJIT",
					},
					workspace = {
						checkThirdParty = false,
						library = {
							vim.env.VIMRUNTIME,
						},
					},
				},
			})

			client.notify("workspace/didChangeConfiguration", { settings = client.config.settings })
		end

		return true
	end,
})
lsp.marksman.setup({})

-- Define icons for gutter
local signs = { Error = " ", Warn = " ", Hint = " ", Info = " " }
for type, icon in pairs(signs) do
	local hl = "DiagnosticSign" .. type
	vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
end
