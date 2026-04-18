-- Wrapped variant of `minimal`: no title/border, just wrapped body with a
-- single space of left/right inline padding per line.
local base = require("notify.render.base")

return function(bufnr, notif, highlights, config)
  local max_width = config.max_width() or 80
  local message = base.custom_wrap(notif.message, max_width, { pad_right = "  " })
  if #message > 0 then
    message[1] = " " .. message[1]
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, message)

  for ln = 1, #message do
    base.set_extmark(bufnr, ln, 0, {
      virt_text = { { " ", highlights.body } },
      virt_text_pos = "inline",
      priority = 50,
    })
    base.set_extmark(bufnr, ln, 0, {
      virt_text = { { " ", highlights.body } },
      virt_text_pos = "right_align",
      priority = 50,
    })
  end
  base.highlight_inline(bufnr, highlights, notif, 0, 0)
end
