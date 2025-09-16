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

  -- Avante and related deps
  {
    "yetone/avante.nvim",
    branch = "main",
    build = "make",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "MeanderingProgrammer/render-markdown.nvim",
      { "hrsh7th/nvim-cmp",          optional = true },
      { "nvim-tree/nvim-web-devicons", optional = true },
      { "HakonHarnes/img-clip.nvim", optional = true },
      { "zbirenbaum/copilot.lua",    optional = true },
      { "stevearc/dressing.nvim",    optional = true },
      { "folke/snacks.nvim",         optional = true },
    },
    config = function()
      require("avante").setup({})
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

