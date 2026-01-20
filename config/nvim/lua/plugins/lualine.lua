return {
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    -- Truncate branch name to max 20 characters
    local branch_max_width = 20
    for i, component in ipairs(opts.sections.lualine_b or {}) do
      if component == "branch" or (type(component) == "table" and component[1] == "branch") then
        opts.sections.lualine_b[i] = {
          "branch",
          fmt = function(name)
            if #name > branch_max_width then
              return name:sub(1, branch_max_width) .. "…"
            end
            return name
          end,
        }
        break
      end
    end
    return opts
  end,
}
