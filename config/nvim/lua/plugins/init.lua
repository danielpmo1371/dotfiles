return {
	-- Telescope
	{
		"nvim-telescope/telescope.nvim",
		branch = "0.1.x",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-tree/nvim-web-devicons",
		},
	},

	-- Treesitter for syntax highlighting
	{
		"nvim-treesitter/nvim-treesitter",
		build = ":TSUpdate",
		config = function()
			local ts = require("nvim-treesitter")
			ts.setup({
				ensure_installed = { "lua", "vim", "vimdoc", "bash", "python", "javascript", "typescript" },
				auto_install = true,
			})
			-- Enable highlighting via vim.treesitter (new API)
			vim.treesitter.language.register("bash", "sh")
		end,
	},

	-- Individual plugins from your previous config
	{ "hashivim/vim-terraform" },
	{ "mg979/vim-visual-multi", branch = "master" },
	{ "nvim-lua/plenary.nvim" },
	{ "MunifTanjim/nui.nvim" },
	{ "MeanderingProgrammer/render-markdown.nvim" },
	{ "hrsh7th/nvim-cmp" },
	{ "nvim-tree/nvim-web-devicons" },
	{ "HakonHarnes/img-clip.nvim" },
	{ "zbirenbaum/copilot.lua" },
	{ "stevearc/dressing.nvim" },
	{ "folke/snacks.nvim" },
}
