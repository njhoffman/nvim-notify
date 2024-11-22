local M = {}

local namespace = vim.api.nvim_create_namespace("nvim-notify")

function M.namespace()
  return namespace
end

-- local generic_hls = function(bufnr, highlights, notif, start_line, start_col, end_line)
--   local body_hl = notif.body_hl_group and notif.body_hl_group or 'body'
--   local opts = {
--     hl_group = highlights[body_hl] or highlights.body,
--     end_line = end_line,
--     priority = 50,
--   }
--   local ok, err = nil, nil
--   if not highlights.repeat_count then
--     -- vim.api.nvim_buf_set_extmark(bufnr, namespace, start_line, start_col, opts)
--     ok, err = pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace(), start_line, start_col, opts)
--   else
--     local repeat_label = '#' .. tostring(notif.repeat_count)
--     opts.end_col = opts.end_col - #repeat_label - 1
--     ok, err = pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace(), start_line, start_col, opts)
--     if not ok then
--       return extmark_fail(err)
--     end
--     -- vim.api.nvim_buf_set_extmark(bufnr, namespace, start_line, start_col, opts)
--     opts.hl_group = highlights.repeat_count
--     start_col = opts.end_col + 1
--     -- opts.end_col = opts.end_col + #repeat_label + 1
--     opts.end_col = -1
--     ok, err = pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace(), start_line, start_col, opts)
--     -- vim.api.nvim_buf_set_extmark(bufnr, namespace, start_line, start_col, opts)
--   end
--   if not ok then
--     extmark_fail(err)
--   end
-- end
--
-- local embedded_hls = function(bufnr, highlights, notif, start_line, start_col)
--   for _, hl in ipairs(notif.highlights.body) do
--     local col = start_col + hl[3]
--     local line = start_line + hl[2]
--     local opts = {
--       hl_group = highlights.content[hl[1]],
--       end_col = hl[4],
--       end_line = line,
--       priority = 60,
--     }
--     vim.api.nvim_buf_set_extmark(bufnr, namespace(), line, col, opts)
--   end
-- end
--
-- local content_hl = function(bufnr, highlights, notif, start_line, start_col, end_line)
--   if vim.tbl_get(notif, 'highlights', 'body') then
--     -- predefined body highlights
--     embedded_hls(bufnr, highlights, notif, start_line, start_col)
--   else
--     -- generic full body highlighting
--     generic_hls(bufnr, highlights, notif, start_line, start_col, end_line)
--   end
-- end
--
-- return { content_hl = content_hl, namespace = namespace }

---@param text string
---@param length number
---@param align "'left'" | "'center'" | "'right'"|nil
---@param gap_char string|nil
---@return string
-- local align_text = function(text, length, align, gap_char)
--   text = tostring(text)
--   align = align or "left"
--   gap_char = gap_char or " "

--   local gap_length = length - vim.api.nvim_strwidth(text)

--   local gap_left = ""
--   local gap_right = ""

--   if align == "left" then
--     gap_right = string.rep(gap_char, gap_length)
--   elseif align == "center" then
--     gap_left = string.rep(gap_char, math.ceil(gap_length / 2))
--     gap_right = string.rep(gap_char, math.floor(gap_length / 2))
--   elseif align == "right" then
--     gap_left = string.rep(gap_char, gap_length)
--   end

--   return gap_left .. text .. gap_right
-- end

-- local align_list = function(list, opts)
--   opts = opts or {}
--   local divider = opts.divider or " "
--   -- local highlights = opts.highlights or { 'NotifyListCol1', 'NotifyListDiv', 'NotifyListCol2' }
--   local highlights = opts.highlights or { "Keyword", "NotifyListDiv", "Comment" }

--   local widths = max_width(list)

--   local lines, hls = {}, {}

--   for i, row in ipairs(list) do
--     local cols = {
--       align_text(row[1], widths[1]),
--       divider,
--       align_text(row[2], widths[2], "right"),
--     }
--     table.insert(hls, { highlights[1], i - 1, 0, #row[1] })
-- j   table.insert(hls, { highlights[2], i - 1, #cols[1], #cols[1] + #cols[2] })
--     table.insert(hls, { highlights[3], i - 1, #cols[1] + #cols[2], #cols[1] + #cols[2] + #cols[3] })

--     local line = vim.fn.join(cols, "")

--     table.insert(lines, line)
--   end
--   return lines, hls
-- end
return M
