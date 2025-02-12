local _ = require("notify.util.underscore")

local debug = {
  flag = false,
}

debug.enable = function()
  debug.flag = true
end
debug.disable = function()
  debug.flag = false
end

local logfmt = {}
logfmt.notification = function(props)
  if not debug.flag then
    return
  end
  vim.dbglog(props.title or "", _.omit(props.notif, { "on_close", "on_open", "render", "keep" }))
end

logfmt.highlights = function(props)
  if not debug.flag then
    return
  end
  vim.dbglog(props.title or "", _.omit(props.buf_highlights, { "_config" }))
end

logfmt.extmarks = function(props)
  if not debug.flag then
    return
  end
  local extmarks =
    vim.api.nvim_buf_get_extmarks(props.buf, -1, 0, -1, { details = true, type = "highlight" })
  local extmarks_out = ""
  for _, extmark in ipairs(extmarks) do
    extmarks_out = extmarks_out
      .. "\n    "
      .. extmark[1]
      .. " "
      .. extmark[2]
      .. ":"
      .. extmark[3]
      .. " - "
      .. extmark[4].end_row
      .. ":"
      .. extmark[4].end_col
      .. " "
      .. extmark[4].hl_group
  end
  vim.dbglog(props.title or "", extmarks_out)
end

debug.logfmt = logfmt

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

return debug
