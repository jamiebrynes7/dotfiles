local function custom_on_attach(bufnr)
	local api = require("nvim-tree.api")

	local function opts(desc)
		return { desc = "nvim-tree: " .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
	end

	-- default mappings
	api.config.mappings.default_on_attach(bufnr)

	-- custom mappings
	vim.keymap.set("n", "<Space>", api.node.open.edit, opts("Open"))
end

require("nvim-tree").setup({
	view = {
		width = 50,
	},
	on_attach = custom_on_attach,
})

require("utils").set_key("n", "tt", ":NvimTreeToggle<CR>")
