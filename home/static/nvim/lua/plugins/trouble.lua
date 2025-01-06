require("trouble").setup {
    action_keys = {
        jump = { "<space>", "<tab>" }
    }
}

require("utils").set_key("n", "td", ":TroubleToggle<CR>")
