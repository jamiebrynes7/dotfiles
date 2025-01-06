local _M = {}

_M.powerline_icons = {
    bar = "▋",
    arrow = {
        right = "",
        left = "",
    },
    git = {
        added = "",
        modified = "",
        removed = "",
        branch = ""
    }
}

_M.set_indent_sizes = function(filetypes)
    for filetype, size in pairs(filetypes) do
        vim.api.nvim_create_autocmd("FileType", {
            pattern = filetype,
            callback = function()
                vim.opt.shiftwidth = size
                vim.opt.tabstop = size
                vim.opt.softtabstop = size
            end
        })
    end
end

local bufopts = { noremap = true, silent = true }

_M.set_key = function(mode, key, command)
    vim.keymap.set(mode, key, command, bufopts)
end

return _M
