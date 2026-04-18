local api = vim.api
local base = require("notify.render.base")

return function(bufnr, notif, highlights)
  local message = notif.message
  if notif.duplicates then
    message = {
      string.format("x%d %s", #notif.duplicates, notif.message[1]),
      unpack(notif.message, 2),
    }
  end
  api.nvim_buf_set_lines(bufnr, 0, -1, false, message)

  base.set_extmark(bufnr, 0, 0, {
    hl_group = highlights.icon,
    end_line = #message - 1,
    end_col = #message[#message],
    priority = 50,
  })
  base.highlight_inline(bufnr, highlights, notif, 0, 0)
end
