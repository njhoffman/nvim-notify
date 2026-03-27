-- Compatibility shim for cross-version Neovim API support (0.9.5+)
local M = {}

-- vim.islist: added in 0.10, replaces vim.tbl_islist
M.islist = vim.islist or vim.tbl_islist

-- vim.isarray: added in 0.10, replaces vim.tbl_islist
M.isarray = vim.isarray or vim.tbl_islist

-- vim.validate: 3-argument form (name, value, type) is 0.11+ only.
-- Translate to old form {[name] = {value, type}} on older versions.
if vim.fn.has("nvim-0.11") == 1 then
  M.validate = vim.validate
else
  M.validate = function(name, value, expected_type)
    vim.validate({ [name] = { value, expected_type } })
  end
end

-- vim.dbglog is non-standard; provide a safe no-op fallback.
M.dbglog = vim.dbglog or function() end

return M
