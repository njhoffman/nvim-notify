--- `lines` decorator: flattens an interpolated nested-table form into
--- plain text + inline highlight ranges.
---
--- Input shape (via `opts.payload.data`):
--- >lua
---     {
---       { { "hello ", "Keyword" }, "world" },   -- line 1: segment + plain
---       { { "line two", "String" } },            -- line 2
---       "plain line three",                      -- line 3 (string = no highlights)
---     }
--- <
--- Each segment is either `{ text, hl_group }` or a plain string.
---
--- Output: `msg` is the flattened string joined by newlines; inline
--- highlights reference the segments that carried a group name.

local M = {}

local function format(opts)
  local data = opts.payload and opts.payload.data
  if type(data) ~= "table" then
    return { msg = "" }
  end

  local lines = {}
  local inline = {}

  for row, entry in ipairs(data) do
    local line_text = ""
    if type(entry) == "string" then
      line_text = entry
    elseif type(entry) == "table" then
      for _, seg in ipairs(entry) do
        local text, hl
        if type(seg) == "string" then
          text = seg
        elseif type(seg) == "table" then
          text = seg[1] or ""
          hl = seg[2]
        end
        text = text or ""
        if hl then
          table.insert(inline, { hl, row - 1, #line_text, #line_text + #text })
        end
        line_text = line_text .. text
      end
    end
    lines[#lines + 1] = line_text
  end

  return {
    msg = table.concat(lines, "\n"),
    highlights = { inline = inline },
    captures = { lines_count = #lines, inline_count = #inline },
  }
end

function M.register(registry)
  registry.register_decorator("lines", {
    trigger = function(opts)
      return opts.payload and opts.payload.kind == "lines"
    end,
    format = function(opts, _)
      return format(opts)
    end,
  })
end

-- Exposed for unit tests.
M._format = format

return M
