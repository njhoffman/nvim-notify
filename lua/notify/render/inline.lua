local api = vim.api
local base = require("notify.render.base")
local util = require("notify.util")

local function utfwidth(str)
  if not str or str == "" then
    return 0
  end
  return vim.api.nvim_strwidth(str)
end

local function resolve_mode(notif)
  local raw = notif.title_input
  if type(raw) == "string" then
    if #raw == 0 then
      return "none"
    end
    return "center", base.apply_duplicates(raw, notif), ""
  end
  if type(raw) == "table" then
    local n = #raw
    if n == 0 then
      return "none"
    end
    if n == 1 then
      local left = raw[1]
      if type(left) ~= "string" or #left == 0 then
        return "none"
      end
      return "left", base.apply_duplicates(left, notif), ""
    end
    local left, right = raw[1], raw[2]
    local left_empty = type(left) ~= "string" or #left == 0
    local right_empty = type(right) ~= "string" or #right == 0
    if left_empty and right_empty then
      return "none"
    end
    if left_empty then
      return "right", "", base.apply_duplicates(right, notif)
    end
    if right_empty then
      return "left", base.apply_duplicates(left, notif), ""
    end
    return "split", base.apply_duplicates(left, notif), right
  end
  return "none"
end

local function render_body(bufnr, notif, highlights, body_start)
  local message = notif.message
  api.nvim_buf_set_lines(bufnr, body_start, -1, false, message)
  base.highlight_body(
    bufnr,
    highlights,
    notif,
    body_start,
    0,
    body_start + #message - 1,
    #message[#message]
  )
  base.highlight_inline(bufnr, highlights, notif, body_start, 0)
end

return function(bufnr, notif, highlights, config)
  local mode, left_title, right_title = resolve_mode(notif)

  if mode == "none" then
    render_body(bufnr, notif, highlights, 0)
    return
  end

  local icon = notif.icon or ""
  local icon_chunk = icon == "" and "" or (icon .. " ")
  local icon_w = utfwidth(icon_chunk)
  local left_w = utfwidth(left_title)
  local right_w = utfwidth(right_title)
  local message_w = util.max_line_width(notif.message)
  local minimum_w = config and config.minimum_width and config.minimum_width() or 0

  local title_block_w
  if mode == "split" then
    title_block_w = icon_w + left_w + right_w + 4
  elseif mode == "right" then
    title_block_w = right_w + 2
  else
    title_block_w = icon_w + left_w + 2
  end

  local bar_width = math.max(message_w, title_block_w + 2, minimum_w)

  api.nvim_buf_set_lines(bufnr, 0, 1, false, { "" })

  if mode == "center" then
    local block_w = icon_w + left_w
    local total_pad = math.max(0, bar_width - block_w - 2)
    local left_pad = math.floor(total_pad / 2)
    local right_pad = total_pad - left_pad
    local chunks = {
      { string.rep("━", left_pad), highlights.border },
      { " " },
    }
    if icon_chunk ~= "" then
      chunks[#chunks + 1] = { icon_chunk, highlights.icon }
    end
    chunks[#chunks + 1] = { left_title, highlights.title }
    chunks[#chunks + 1] = { " " }
    chunks[#chunks + 1] = { string.rep("━", right_pad), highlights.border }
    base.set_extmark(bufnr, 0, 0, {
      virt_text = chunks,
      virt_text_win_col = 0,
      priority = 10,
    })
  elseif mode == "left" then
    local trailing = math.max(0, bar_width - icon_w - left_w - 2)
    local chunks = { { " " } }
    if icon_chunk ~= "" then
      chunks[#chunks + 1] = { icon_chunk, highlights.icon }
    end
    chunks[#chunks + 1] = { left_title, highlights.title }
    chunks[#chunks + 1] = { " " }
    chunks[#chunks + 1] = { string.rep("━", trailing), highlights.border }
    base.set_extmark(bufnr, 0, 0, {
      virt_text = chunks,
      virt_text_win_col = 0,
      priority = 10,
    })
  elseif mode == "right" then
    local leading = math.max(0, bar_width - right_w - 2)
    base.set_extmark(bufnr, 0, 0, {
      virt_text = { { string.rep("━", leading), highlights.border } },
      virt_text_win_col = 0,
      priority = 10,
    })
    base.set_extmark(bufnr, 0, 0, {
      virt_text = { { " " }, { right_title, highlights.title }, { " " } },
      virt_text_pos = "right_align",
      priority = 10,
    })
  else
    local middle = math.max(0, bar_width - icon_w - left_w - right_w - 4)
    local left_chunks = { { " " } }
    if icon_chunk ~= "" then
      left_chunks[#left_chunks + 1] = { icon_chunk, highlights.icon }
    end
    left_chunks[#left_chunks + 1] = { left_title, highlights.title }
    left_chunks[#left_chunks + 1] = { " " }
    left_chunks[#left_chunks + 1] = { string.rep("━", middle), highlights.border }
    base.set_extmark(bufnr, 0, 0, {
      virt_text = left_chunks,
      virt_text_win_col = 0,
      priority = 10,
    })
    base.set_extmark(bufnr, 0, 0, {
      virt_text = { { " " }, { right_title, highlights.title }, { " " } },
      virt_text_pos = "right_align",
      priority = 10,
    })
  end

  render_body(bufnr, notif, highlights, 1)
end
