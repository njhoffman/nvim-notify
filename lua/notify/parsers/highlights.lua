-- handles tables in notification message that either contain body highlights or objects to inspect
-- returns plain string and table of lines each containing arrays of { Content, HLName? }

-- todo: better version of this where it scans table and ensures never more than two elements
local has_embedded_hls = function(msg)
  return type(msg[1]) == "table" and type(msg[1][1]) == "table" and type(msg[1][1][1]) == "string"
end

local gen_highlights = function(orig_msg)
  local msg = ""
  local highlights = {}
  for n, line in ipairs(orig_msg) do
    if n > 1 then
      msg = msg .. "\n"
    end
    local line_msg = ""
    for _, v in ipairs(line) do
      line_msg = line_msg .. v[1]
      if v[2] then
        table.insert(highlights, { v[2], n - 1, #line_msg - #v[1], #line_msg })
      end
    end
    msg = msg .. line_msg
  end
  return msg, highlights
end

local parse_message = function(orig_msg, orig_opts)
  local new_opts = orig_opts or {}
  local new_msg = orig_msg or ""
  local highlights = {}
  if type(new_msg) == "table" then
    if vim.islist(orig_msg) then
      if type(orig_msg[1]) == "string" then
        new_msg = vim.fn.join(orig_msg, "\n")
      elseif has_embedded_hls(orig_msg) then
        new_msg, highlights = gen_highlights(orig_msg)
        new_opts.highlights =
          vim.tbl_deep_extend("force", new_opts.highlights or {}, { body = highlights })
      else
        new_opts.filetype = orig_opts.filetype or ""
        new_msg = vim.inspect(orig_msg)
      end
    else
      new_opts.filetype = orig_opts.filetype or ""
      new_msg = vim.inspect(orig_msg)
    end
  end
  return new_msg, new_opts
end

return parse_message
