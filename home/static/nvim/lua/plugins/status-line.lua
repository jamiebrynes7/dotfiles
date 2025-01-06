local gl = require('galaxyline')

local gls = gl.section
gl.short_line_list = { "NvimTree" }
gls.short_line_left = {}
gls.short_line_right = {}

local condition = require('galaxyline.condition')

local nord_colors = require('nord.named_colors')
local colors = {
    fg = nord_colors.white,
    fg_dark = nord_colors.glacier,
    bg = nord_colors.black,
    section_bg = nord_colors.dark_gray,
    section_bg_light = nord_colors.gray,
    green = nord_colors.green,
    orange = nord_colors.orange,
    red = nord_colors.red,
    purple = nord_colors.purple,
    glacier = nord_colors.glacier,
    dark = "#1C1F27"
}

local mode_color = function()
    local mode_colors = {
        n = nord_colors.teal,
        i = nord_colors.green,
        c = nord_colors.orange,
        V = nord_colors.purple,
        [''] = nord_colors.purple,
        v = nord_colors.purple,
        R = nord_colors.red
    }

    local color = mode_colors[vim.fn.mode()]
    if color == nil then color = nord_colors.red end

    return color
end

local buffer_not_empty = function()
    if vim.fn.empty(vim.fn.expand('%:t')) ~= 1 then
        return true
    end
    return false
end

local powerline_icons = require("utils").powerline_icons

-- Left side
gls.left[1] = {
  ViMode = {
    provider = function()
      local alias = {
        n = 'NORMAL',
        i = 'INSERT',
        c = 'COMMAND',
        V = 'VISUAL',
        [''] = 'VISUAL',
        v = 'VISUAL',
        R = 'REPLACE'
      }
      vim.api.nvim_command('hi GalaxyViMode guifg=' .. mode_color())
      local alias_mode = alias[vim.fn.mode()]
      if alias_mode == nil then alias_mode = vim.fn.mode() end
      return "  " .. alias_mode .. " "
    end,
    icon = powerline_icons.bar,
    highlight = {colors.bg, colors.dark, 'bold'},
    separator = powerline_icons.arrow.right .. " ",
    separator_highlight = { colors.dark, colors.bg }
  }
}

gls.left[2] = {
  FileIcon = {
    provider = 'FileIcon',
    condition = buffer_not_empty,
    highlight = {
        require('galaxyline.provider_fileinfo').get_file_icon_color,
        colors.bg
    }
  }
}
gls.left[3] = {
    FileName = {
        provider = 'FileName',
        condition = buffer_not_empty,
        highlight = { colors.fg_dark, colors.bg },
    }
}

-- Right side
gls.right[1] = {
  DiffAdd = {
    provider = 'DiffAdd',
    condition = condition.check_git_workspace,
    icon = " " .. powerline_icons.git.added .. " ",
    highlight = {colors.green, colors.dark},
    separator = powerline_icons.arrow.left,
    separator_highlight = {colors.dark, colors.bg}
  }
}
gls.right[2] = {
  DiffModified = {
    provider = 'DiffModified',
    condition = condition.check_git_workspace,
    icon = " " .. powerline_icons.git.modified .. " ",
    highlight = {colors.orange, colors.dark}
  }
}
gls.right[3] = {
  DiffRemove = {
    provider = 'DiffRemove',
    condition = condition.check_git_workspace,
    icon = " " .. powerline_icons.git.removed .. " ",
    highlight = {colors.red, colors.dark}
  }
}

gls.right[4] = {
    GitBranch = {
        provider = function()
            local vcs = require('galaxyline.provider_vcs')
            local branch_name = vcs.get_git_branch()
            if (string.len(branch_name) > 28) then
                return string.sub(branch_name, 1, 25) .. "..."
            end
            return branch_name .. " "
        end,
        condition = condition.check_git_workspace,
        highlight = {colors.purple, colors.dark},
        icon = " " .. powerline_icons.git.branch .. " ",
    }
}


