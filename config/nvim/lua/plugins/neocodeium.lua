-- return {
-- 	"monkoose/neocodeium",
-- 	event = "VeryLazy",
-- 	config = function()
-- 		local neocodeium = require("neocodeium")
-- 		neocodeium.setup()
-- 		vim.keymap.set("i", "<A-f>", neocodeium.accept)
-- 	end,
-- }
return {
	"monkoose/neocodeium",
	event = "InsertEnter", -- or "VeryLazy"
	config = function()
		local neocodeium = require("neocodeium")
		neocodeium.setup()

		-- example keymaps
		vim.keymap.set("i", "<C-f>", neocodeium.accept)
		vim.keymap.set("i", "<C-n>", neocodeium.cycle_or_complete)
		vim.keymap.set("i", "<C-x>", neocodeium.clear)
	end,
}
