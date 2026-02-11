-- Keymaps 
vim.keymap.set("n", "<leader>X", "<cmd>LazyExtras<cr>", { desc = "LazyExtras" })

vim.keymap.set("n", "ff", "<cmd>Telescope find_files<cr>", { silent = true })
vim.keymap.set("n", "fg", "<cmd>Telescope live_grep<cr>", { silent = true })
vim.keymap.set("n", "<leader>fb", "<cmd>Telescope buffers<cr>", { silent = true })
vim.keymap.set("n", "<leader>fh", "<cmd>Telescope help_tags<cr>", { silent = true })

-- Cycle buffers with Tab, cycle windows with Shift+Tab
vim.keymap.set("n", "<Tab>", "<cmd>bnext<cr>", { desc = "Next buffer" })
vim.keymap.set("n", "<S-Tab>", "<C-w>w", { desc = "Next window" })
