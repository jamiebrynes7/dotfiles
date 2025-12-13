require("settings")

local plugins = {
	-- Load theme first before anything else
	"tokyonight",

	"cmp",
	"gitsigns",
	"indent-blankline",
	"nvim-tree",
	"telescope",
	"treesitter",
}

-- Import plugins
for _, name in ipairs(plugins) do
	local path = "plugins/" .. name
	require(path)
end
