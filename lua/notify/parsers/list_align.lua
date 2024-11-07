local max_width = function(lines)
  local max = {}
  for _, line in ipairs(lines) do
    local cols = vim.isarray(line) and line or { line }
    for i, col in ipairs(cols) do
      max[i] = math.max(#tostring(col), max[i] or 0)
    end
  end
  return #max == 1 and max[1] or max
end

---@param text string
---@param length number
---@param align "'left'" | "'center'" | "'right'"|nil
---@param gap_char string|nil
---@return string
local align_text = function(text, length, align, gap_char)
  text = tostring(text)
  align = align or 'left'
  gap_char = gap_char or ' '

  local gap_length = length - vim.api.nvim_strwidth(text)
  local gap_left = ''
  local gap_right = ''

  if align == 'left' then
    gap_right = string.rep(gap_char, gap_length)
  elseif align == 'center' then
    gap_left = string.rep(gap_char, math.ceil(gap_length / 2))
    gap_right = string.rep(gap_char, math.floor(gap_length / 2))
  elseif align == 'right' then
    gap_left = string.rep(gap_char, gap_length)
  end
  return gap_left .. text .. gap_right
end

local list_align = function(list, opts)
  opts = opts or {}
  local divider = opts.divider or ' '
  -- local highlights = opts.highlights or { 'NotifyListCol1', 'NotifyListDiv', 'NotifyListCol2' }
  local highlights = opts.highlights or { 'Keyword', 'NotifyListDiv', 'Comment' }
  local widths = max_width(list)
  local lines, hls = {}, {}
  for i, row in ipairs(list) do
    local cols = {
      align_text(row[1], widths[1]),
      divider,
      align_text(row[2], widths[2], 'right'),
    }
    table.insert(hls, { highlights[1], i - 1, 0, #row[1] })
    table.insert(hls, { highlights[2], i - 1, #cols[1], #cols[1] + #cols[2] })
    table.insert(hls, { highlights[3], i - 1, #cols[1] + #cols[2], #cols[1] + #cols[2] + #cols[3] })

    local line = vim.fn.join(cols, '')
    table.insert(lines, line)
  end
  return lines, hls
end

return list_align
