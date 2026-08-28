return {
	{
		"mason-org/mason.nvim",
		opts = function(_, opts)
			opts.ensure_installed = opts.ensure_installed or {}
			-- Remove packages pulled by extras that we don't want
			-- netcoredbg: dotnet extra forces the DAP debugger in even without dap.core
			local blocked = { "fantomas", "netcoredbg" }
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
			-- Dedupe: LazyVim installs each entry blindly and a duplicate
			-- (e.g. prettier from the extra + this list) aborts all installs
			local seen, deduped = {}, {}
			for _, pkg in ipairs(opts.ensure_installed) do
				if not seen[pkg] then
					seen[pkg] = true
					table.insert(deduped, pkg)
				end
			end
			opts.ensure_installed = deduped
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
