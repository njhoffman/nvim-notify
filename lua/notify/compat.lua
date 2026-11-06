-- Single place to change if these Neovim APIs move. Requires Neovim 0.11+.
local M = {}

M.islist = vim.islist
M.isarray = vim.isarray
M.validate = vim.validate

return M
