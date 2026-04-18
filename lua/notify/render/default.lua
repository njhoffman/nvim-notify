local api = vim.api
local base = require("notify.render.base")
local util = require("notify.util")

return function(bufnr, notif, highlights, config)
  local left_icon = notif.icon == "" and "" or notif.icon .. " "
  local max_message_width = util.max_line_width(notif.message)
  local right_title = notif.title[2]
  local left_title = base.apply_duplicates(notif.title[1], notif)

  local title_accum = vim.str_utfindex(left_icon)
    + vim.str_utfindex(right_title)
    + vim.str_utfindex(left_title)

  local left_buffer = string.rep(" ", math.max(0, max_message_width - title_accum))

  api.nvim_buf_set_lines(bufnr, 0, 1, false, { "", "" })
  base.set_extmark(bufnr, 0, 0, {
    virt_text = {
      { " " },
      { left_icon, highlights.icon },
      { left_title .. left_buffer, highlights.title },
    },
    virt_text_win_col = 0,
    priority = 10,
  })
  base.set_extmark(bufnr, 0, 0, {
    virt_text = { { " " }, { right_title, highlights.title }, { " " } },
    virt_text_pos = "right_align",
    priority = 10,
  })
  base.set_extmark(bufnr, 1, 0, {
    virt_text = {
      {
        string.rep(
          "━",
          math.max(vim.str_utfindex(left_buffer) + title_accum + 2, config.minimum_width())
        ),
        highlights.border,
      },
    },
    virt_text_win_col = 0,
    priority = 10,
  })

  local message = notif.message
  api.nvim_buf_set_lines(bufnr, 2, -1, false, message)

  base.highlight_body(bufnr, highlights, notif, 2, 0, 1 + #message, #message[#message])
  base.highlight_inline(bufnr, highlights, notif, 2, 0)
end
