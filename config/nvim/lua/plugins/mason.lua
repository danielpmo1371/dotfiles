return {
	{
		"williamboman/mason.nvim",
		opts = function(_, opts)
			opts.ensure_installed = opts.ensure_installed or {}
			-- Remove packages pulled by extras that we don't want
			local blocked = { "fantomas" }
			opts.ensure_installed = vim.tbl_filter(function(pkg)
				return not vim.tbl_contains(blocked, pkg)
			end, opts.ensure_installed)
			-- Add our explicit packages
			vim.list_extend(opts.ensure_installed, {
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
			})
		end,
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
