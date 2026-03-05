return {
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				-- LSP servers
				"pyright",
				"lua-language-server",
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

	-- Disable LSPs we don't need (pulled in by LazyVim extras)
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				-- F# and PowerShell from dotnet extra
				fsautocomplete = { enabled = false },
				powershell_es = { enabled = false },
				-- Redundant C# LSP (using omnisharp)
				csharp_ls = { enabled = false },
				-- Using pyright + black instead
				ruff = { enabled = false },
			},
		},
	},
}
