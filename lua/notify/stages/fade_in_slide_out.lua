local stages_util = require("notify.stages.util")

local opacity = 85
local freq = { 3, 3, 2.5, 2, 3 }
-- local freq = { 5, 5, 2.5, 2, 3 }

return function(direction)
  return {
    function(state)
      local next_height = state.message.height + 2
      local next_row = stages_util.available_slot(state.open_windows, next_height, direction)
      if not next_row then
        return nil
      end
      return {
        relative = "editor",
        anchor = "NE",
        width = state.message.width,
        height = state.message.height,
        col = vim.opt.columns:get(),
        row = next_row,
        border = "rounded",
        style = "minimal",
        opacity = 0,
      }
    end,
    function(state, win)
      return {
        opacity = { opacity },
        col = { vim.opt.columns:get() },
        row = {
          stages_util.slot_after_previous(win, state.open_windows, direction),
          frequency = freq[1],
          complete = function()
            return true
          end,
        },
      }
    end,
    function(state, win)
      return {
        col = { vim.opt.columns:get() },
        time = true,
        row = {
          stages_util.slot_after_previous(win, state.open_windows, direction),
          frequency = freq[2],
          complete = function()
            return true
          end,
        },
      }
    end,
    function(state, win)
      return {
        width = {
          1,
          frequency = freq[3],
          damping = 0.9,
          complete = function(cur_width)
            return cur_width < 3
          end,
        },
        opacity = {
          0,
          frequency = freq[4],
          complete = function(cur_opacity)
            return cur_opacity <= 4
          end,
        },
        col = { vim.opt.columns:get() },
        row = {
          stages_util.slot_after_previous(win, state.open_windows, direction),
          frequency = freq[5],
          complete = function()
            return true
          end,
        },
      }
    end,
  }
end
