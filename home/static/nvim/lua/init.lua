require("settings")

local plugins = {
	-- Load theme first before anything else
	"tokyonight",

	"barbecue",
	"cmp",
	"conform",
	"fidget",
	"gitsigns",
	"indent-blankline",
	"lspconfig",
	"nvim-tree",
	"symbols-outline",
	"telescope",
	"treesitter",
	"trouble",
}

-- Import plugins
for _, name in ipairs(plugins) do
	local path = "plugins/" .. name
	require(path)
end
