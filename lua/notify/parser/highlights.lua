local has_highlights = function(msg)
  -- TODO: scan message and verify highlights
  return type(msg) == "table" and type(msg[1]) == "table" and type(msg[1][1]) == "string"
end

local get_highlights = function(msg)
  local highlights = {}
  for n, line in ipairs(msg) do
    local _msg = ""
    if n > 1 then
      _msg = _msg .. "\n"
    end
    local line_msg = ""
    for _, v in ipairs(line) do
      line_msg = line_msg .. v[1]
      if v[2] then
        table.insert(highlights, { v[2], n - 1, #line_msg - #v[1], #line_msg })
      end
    end
    _msg = _msg .. line_msg
    return _msg, highlights
  end
  return msg, highlights
end

local parse_highlights = function(msg, level, opts)
  if has_highlights(msg) then
    local _msg, highlights = get_highlights(msg)
    opts.highlights = vim.tbl_deep_extend("force", opts.highlights or {}, {
      body = highlights,
    })
    return _msg, level, opts
  end
  return msg, level, opts
end

return parse_highlights
