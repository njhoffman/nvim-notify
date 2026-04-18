--- `columns` decorator: aligns structured rows into justified columns
--- with optional per-column highlight groups.
---
--- Payload shape (`opts.payload.data`):
--- >lua
---     {
---       rows = {
---         { "apple",  "1"  },
---         { "banana", "42" },
---       },
---       columns = {               -- optional; defaults to { align = "left" }
---         { align = "left",  highlight = "Keyword" },
---         { align = "right", highlight = "Comment" },
---       },
---       separator = " ",          -- between columns, default " "
---       min_widths = { 10, 5 },   -- optional, per-column lower bound
---     }
--- <

local M = {}

local function max_display_width(rows, column_count)
  local widths = {}
  for i = 1, column_count do
    widths[i] = 0
  end
  for _, row in ipairs(rows) do
    for i = 1, column_count do
      local cell = row[i] or ""
      local w = vim.str_utfindex(cell)
      if w > widths[i] then
        widths[i] = w
      end
    end
  end
  return widths
end

local function pad(text, width, align)
  local w = vim.str_utfindex(text)
  if w >= width then
    return text
  end
  local spaces = width - w
  if align == "right" then
    return string.rep(" ", spaces) .. text
  elseif align == "center" then
    local left = math.floor(spaces / 2)
    local right = spaces - left
    return string.rep(" ", left) .. text .. string.rep(" ", right)
  end
  return text .. string.rep(" ", spaces)
end

local function format(opts)
  local data = opts.payload and opts.payload.data or {}
  local rows = data.rows or {}
  if #rows == 0 then
    return { msg = "" }
  end

  local column_count = 0
  for _, row in ipairs(rows) do
    if #row > column_count then
      column_count = #row
    end
  end

  local cols = data.columns or {}
  local separator = data.separator or " "
  local widths = max_display_width(rows, column_count)
  for i, min in ipairs(data.min_widths or {}) do
    if min and min > (widths[i] or 0) then
      widths[i] = min
    end
  end

  local lines = {}
  local inline = {}

  for row_idx, row in ipairs(rows) do
    local cells = {}
    local cursor = 0
    for i = 1, column_count do
      local raw = row[i] or ""
      local col = cols[i] or {}
      local padded = pad(raw, widths[i], col.align or "left")
      local start_col = cursor
      local end_col = cursor + #padded
      cells[i] = padded
      if col.highlight then
        table.insert(inline, { col.highlight, row_idx - 1, start_col, end_col })
      end
      cursor = end_col + #separator
    end
    lines[#lines + 1] = table.concat(cells, separator)
  end

  return {
    msg = table.concat(lines, "\n"),
    highlights = { inline = inline },
    captures = {
      layout = "columns",
      row_count = #rows,
      column_count = column_count,
    },
  }
end

function M.register(registry)
  registry.register_decorator("columns", {
    trigger = function(opts)
      return opts.payload and opts.payload.kind == "columns"
    end,
    format = function(opts, _)
      return format(opts)
    end,
  })
end

M._format = format

return M
