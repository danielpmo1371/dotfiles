-- Seamless nvim-split <-> tmux-pane navigation.
-- Pairs with the vim-aware C-h/j/k/l and M-h/j/k/l binds in config/tmux/tmux.conf
-- (is_vim pattern): inside nvim these keys move between splits, at a split edge
-- the plugin hands the move over to tmux.
-- Meta family = Alt on Linux, Option (and Cmd via Ghostty adapter) on macOS.
return {
  "christoomey/vim-tmux-navigator",
  cmd = {
    "TmuxNavigateLeft",
    "TmuxNavigateDown",
    "TmuxNavigateUp",
    "TmuxNavigateRight",
    "TmuxNavigatePrevious",
  },
  keys = {
    { "<C-h>", "<cmd>TmuxNavigateLeft<cr>" },
    { "<C-j>", "<cmd>TmuxNavigateDown<cr>" },
    { "<C-k>", "<cmd>TmuxNavigateUp<cr>" },
    { "<C-l>", "<cmd>TmuxNavigateRight<cr>" },
    { "<A-h>", "<cmd>TmuxNavigateLeft<cr>" },
    { "<A-j>", "<cmd>TmuxNavigateDown<cr>" },
    { "<A-k>", "<cmd>TmuxNavigateUp<cr>" },
    { "<A-l>", "<cmd>TmuxNavigateRight<cr>" },
  },
}
