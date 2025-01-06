local line_ok, feline = pcall(require, "feline")
if not line_ok then
	return
end

local colors = require("tokyonight.colors").setup({ style = "night" })
local tokyonight_night_theme = {
	fg = colors.fg,
	fg_dark = colors.fg_dark,
	bg = colors.bg,
	bg_dark = colors.bg_dark,
	green = colors.green,
	yellow = colors.yellow,
	purple = colors.purple,
	orange = colors.orange,
	red = colors.red,
	aqua = colors.teal,
	dark_red = colors.red1,
}

local vi_mode_colors = {
	NORMAL = "green",
	OP = "green",
	INSERT = "yellow",
	VISUAL = "purple",
	LINES = "orange",
	BLOCK = "dark_red",
	REPLACE = "red",
	COMMAND = "aqua",
}

local separators = require("feline.defaults").statusline.separators.default_value
local vi_mode_provider = require("feline.providers.vi_mode")

local c = {
	vim_mode = {
		provider = {
			name = "vi_mode",
			opts = {
				show_mode_name = true,
				padding = "center",
			},
		},
		hl = function()
			return {
				fg = "bg",
				bg = vi_mode_provider.get_mode_color(),
				name = "NeovimModeHLColor",
			}
		end,
		left_sep = {
			str = separators.block,
			hl = function()
				return {
					fg = vi_mode_provider.get_mode_color(),
				}
			end,
		},
		right_sep = {
			str = separators.right_filled,
			hl = function()
				return {
					fg = vi_mode_provider.get_mode_color(),
				}
			end,
		},
	},
	gitBranch = {
		provider = "git_branch",
		hl = {
			fg = "bg_dark",
			bg = "fg_dark",
		},
		left_sep = {
			str = string.format("%s ", separators.right_filled),
			hl = {
				fg = "bg_dark",
				bg = "fg_dark",
			},
		},
		right_sep = {
			str = separators.right_filled,
			hl = {
				fg = "fg_dark",
			},
		},
	},
	empty = {
		provider = "",
	},
	diagnostic_errors = {
		provider = "diagnostic_errors",
		hl = {
			fg = "red",
		},
	},
	diagnostic_warnings = {
		provider = "diagnostic_warnings",
		hl = {
			fg = "yellow",
		},
	},
	diagnostic_hints = {
		provider = "diagnostic_hints",
		hl = {
			fg = "aqua",
		},
	},
	diagnostic_info = {
		provider = "diagnostic_info",
	},
	lsp_client_names = {
		provider = "lsp_client_names",
		hl = {
			fg = "purple",
		},
		left_sep = "left_filled",
		right_sep = "block",
	},
	file_type = {
		provider = {
			name = "file_type",
			opts = {
				filetype_icon = true,
				case = "lowercase",
			},
		},
		hl = {
			fg = "red",
		},
		left_sep = "block",
		right_sep = "block",
	},
	position = {
		provider = "position",
		hl = {
			fg = "green",
		},
		left_sep = "block",
		right_sep = "block",
	},
	line_percentage = {
		provider = "line_percentage",
		hl = {
			fg = "aqua",
		},
		left_sep = "block",
		right_sep = "block",
	},
}

local left = {
	c.vim_mode,
	c.gitBranch,
	c.empty,
}

local middle = {}

local right = {
	c.diagnostic_errors,
	c.diagnostic_warnings,
	c.diagnostic_info,
	c.diagnostic_hints,
	c.lsp_client_names,
	c.file_type,
	c.position,
}

local components = {
	active = {
		left,
		middle,
		right,
	},
	inactive = {},
}

feline.setup({
	components = components,
	theme = tokyonight_night_theme,
	vi_mode_colors = vi_mode_colors,
})
