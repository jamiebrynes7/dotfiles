-- Vim configuration
vim.cmd [[filetype plugin indent on]]
vim.cmd [[syntax on]]
vim.cmd [[autocmd BufWritePre * lua vim.lsp.buf.format()]]
vim.g.mapleader = " "

local options = {
    autoindent = true,
    compatible = false,
    clipboard = "unnamedplus",
    encoding = "UTF-8",
    expandtab = true,
    guifont = "JetBrains Mono Nerd Font:h10",
    number = true,
    signcolumn = auto,
    shiftwidth = 4,
    showmatch = true,
    showmode = false,
    swapfile = false,
    tabstop = 4,
    termguicolors = true,
    wildmode = { "longest", "list" },
}

for key, value in pairs(options) do
    vim.opt[key] = value
end

local utils = require("utils")
require("utils").set_indent_sizes({
    html = 2,
    svelte = 2,
    nix = 2,
})


-- Key remaps
utils.set_key('n', '<Space>', '<Nop>')
utils.set_key('n', '<Leader>w', '<C-w>')
utils.set_key('n', '<F2>', ':noh<CR>')

