local api = vim.api
local base = require("notify.render.base")
local util = require("notify.util")

return function(bufnr, notif, highlights, config)
  local max_message_width = util.max_line_width(notif.message)
  local title = base.apply_duplicates(notif.title[1], notif)

  local title_accum = vim.str_utfindex(title)
  local bar_width = math.max(max_message_width, title_accum, config.minimum_width())
  local title_buffer = string.rep(" ", (bar_width - title_accum) / 2)

  api.nvim_buf_set_lines(bufnr, 0, 1, false, { "", "" })
  base.set_extmark(bufnr, 0, 0, {
    virt_text = {
      { title_buffer .. title .. title_buffer, highlights.title },
    },
    virt_text_win_col = 0,
    priority = 10,
  })
  base.set_extmark(bufnr, 1, 0, {
    virt_text = {
      { string.rep("━", bar_width), highlights.border },
    },
    virt_text_win_col = 0,
    priority = 10,
  })
  local message = notif.message
  api.nvim_buf_set_lines(bufnr, 2, -1, false, message)

  base.highlight_body(bufnr, highlights, notif, 2, 0, 1 + #message, #message[#message])
  base.highlight_inline(bufnr, highlights, notif, 2, 0)
end
