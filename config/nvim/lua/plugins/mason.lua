return {
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				-- LSP servers
				"pyright",
				"lua-language-server",
				"typescript-language-server",
				"terraform-ls",
				-- Formatters
				"prettier",
				"stylua",
				"black",
				-- Linters
				"eslint-lsp",
				"shellcheck",
			},
		},
	},
}
