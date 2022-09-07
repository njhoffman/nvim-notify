local stages_util = require("notify.stages.util")

local opacity = 100
local width = 0

local get_col = function(state)
  local anchor = state.anchor or "TR"
  local col = vim.opt.columns:get()
  if anchor == "TC" or anchor == "BC" or anchor == "C" then
    col = vim.opt.columns:get() / 2 + width / 2
  elseif anchor == "TL" or anchor == "BL" then
    col = 1
  end
  return col
end

local get_row = function(state, next_height, direction)
  local next_row = stages_util.available_slot(state.open_windows, next_height, direction)
  if not next_row then
    return nil
  end
  return next_row
end

return function(direction)
  return {
    function(state)
      width = state.message.width
      local next_height = state.message.height + 2
      return {
        relative = "editor",
        anchor = "NE",
        width = state.message.width,
        height = state.message.height,
        col = get_col(state),
        row = get_row(state, next_height, direction),
        border = "rounded",
        style = "minimal",
        opacity = 0,
      }
    end,
    function(state)
      return {
        opacity = { opacity },
        col = { get_col(state) },
      }
    end,
    function(state)
      return {
        col = { get_col(state) },
        time = true,
      }
    end,
    function(state)
      return {
        opacity = {
          0,
          frequency = 2,
          complete = function(cur_opacity)
            return cur_opacity <= 4
          end,
        },
        col = { get_col(state) },
      }
    end,
  }
end
