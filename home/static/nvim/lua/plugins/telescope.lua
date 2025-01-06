local ts = require("telescope")
ts.setup { 
    pickers = {
        find_files = {
            theme = "ivy",
        },
        git_files = {
            theme = "ivy",
            hidden = "true",
            show_untracked = "true"
        },
        live_grep = {
            theme = "ivy"
        },
        lsp_document_symbols = {
            theme = "ivy"
        },
        lsp_workspace_symbols = {
            theme = "ivy"
        },
        buffers = {
            theme = "ivy"
        }
    },
    extensions = { }
}

local utils = require("utils")
utils.set_key('n', 'fb', ':Telescope buffers<CR>')
utils.set_key('n', 'ff', ':Telescope git_files<CR>')
utils.set_key('n', 'fa', ':Telescope find_files<CR>')
utils.set_key('n', 'fg', ':Telescope live_grep<CR>')
utils.set_key('n', 'fs', ':Telescope lsp_document_symbols<CR>')
utils.set_key('n', 'fw', ':Telescope lsp_workspace_symbols<CR>')
utils.set_key('n', 'fr', ':Telescope lsp_references<CR>')
