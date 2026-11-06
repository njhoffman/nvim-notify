local api = vim.api
local base = require("notify.render.base")
local util = require("notify.util")

return function(bufnr, notif, highlights, config)
  local left_icon = notif.icon == "" and "" or notif.icon .. " "
  local max_message_width = util.max_line_width(notif.message)
  local right_title = notif.title[2]
  local max_width = base.max_width(config)
  -- The row is " <icon><title>" and " <time> " aligned right.
  local available = max_width
    and max_width - 3 - vim.fn.strdisplaywidth(left_icon) - vim.fn.strdisplaywidth(right_title)
  local left_title = base.fit_title(notif.title[1], notif, available)

  local title_accum = vim.str_utfindex(left_icon, "utf-32")
    + vim.str_utfindex(right_title, "utf-32")
    + vim.str_utfindex(left_title, "utf-32")

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
          math.max(
            vim.str_utfindex(left_buffer, "utf-32") + title_accum + 2,
            config.minimum_width()
          )
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
