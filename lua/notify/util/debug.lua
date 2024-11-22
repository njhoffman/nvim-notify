local debug = { flag = true }

debug.enable = function()
  debug.flag = true
end
debug.disable = function()
  debug.flag = false
end

debug.fmt = {}

debug.log = function(...)
  if debug.flag == true then
    local data = {}
    for _, v in ipairs({ ... }) do
      if not vim.tbl_contains({ "string", "number", "boolean" }, type(v)) then
        v = vim.inspect(v)
      end
      table.insert(data, v)
    end
    vim.dbglog(table.concat(data, " "))
  end
end
