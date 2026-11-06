local api = vim.api
local animate = require("notify.animate")
local util = require("notify.util")
local log = require("notify.util.log")
local round = util.round
local max = math.max

---@class WindowAnimator
---@field config table
---@field win_states table<number, table<string, SpringState>>
---@field win_stages table<number, integer>
---@field notif_bufs table<number, NotificationBuf>
---@field timers table
---@field stages table
---@field on_wake function|nil Called when a window needs the render loop running at full speed
---@field _dirty table<number, boolean> Windows that changed since the last flush
---@field _needs_flush boolean
local WindowAnimator = {}

function WindowAnimator:new(stages, config)
  local animator = {
    config = config,
    win_stages = {},
    win_states = {},
    notif_bufs = {},
    timers = {},
    stages = stages,
    _dirty = {},
    _needs_flush = false,
  }
  self.__index = self
  setmetatable(animator, self)
  return animator
end

---@return boolean active Whether any windows are still open
---@return boolean settled Whether every window is waiting in its timed stage with nothing to animate
function WindowAnimator:render(queue, time)
  self:push_pending(queue)
  if vim.tbl_isempty(self.win_stages) then
    self:_flush()
    return false, false
  end
  local open_windows = vim.tbl_keys(self.win_stages)
  local settled = true
  for win, _ in pairs(self.win_stages) do
    if not self:_update_window(time, win, open_windows) then
      settled = false
    end
  end
  self:_flush()
  return true, settled
end

--- Repaint the windows that changed, then flush once so the result is shown during blocking events.
function WindowAnimator:_flush()
  local function redraw(opts)
    local ok, err = pcall(api.nvim__redraw, opts)
    if not ok then
      log.error("nvim-notify: Failed to redraw: ", err)
    end
  end
  for win, _ in pairs(self._dirty) do
    self._dirty[win] = nil
    if api.nvim_win_is_valid(win) then
      redraw({ win = win, valid = false })
      self._needs_flush = true
    end
  end
  if self._needs_flush then
    self._needs_flush = false
    redraw({ flush = true })
  end
end

function WindowAnimator:_wake()
  if self.on_wake then
    self.on_wake()
  end
end

function WindowAnimator:push_pending(queue)
  if queue:is_empty() then
    return
  end
  while not queue:is_empty() do
    ---@type NotificationBuf
    local notif_buf = queue:peek()
    if not notif_buf:is_valid() then
      queue:pop()
    else
      local windows = vim.tbl_keys(self.win_stages)
      local win_opts = self.stages[1]({
        message = self:_get_dimensions(notif_buf),
        open_windows = windows,
      })
      if not win_opts then
        return
      end
      local opacity = util.pop(win_opts, "opacity")
      if opacity then
        notif_buf.highlights:set_opacity(opacity)
      end
      win_opts.noautocmd = true

      if notif_buf:is_valid() then
        local win = util.open_win(notif_buf, false, win_opts)
        vim.fn.setwinvar(
          win,
          "&winhl",
          "NormalNC:NONE"
            .. ",Normal:"
            .. notif_buf.highlights.body
            .. ",FloatBorder:"
            .. notif_buf.highlights.border
        )
        notif_buf.highlights:attach(win)
        self.win_stages[win] = 2
        self.win_states[win] = {}
        self.notif_bufs[win] = notif_buf
        self._dirty[win] = true
        queue:pop()
        notif_buf:open(win)
      end
    end
  end
end

function WindowAnimator:_advance_win_stage(win)
  local cur_stage = self.win_stages[win]
  if not cur_stage then
    return
  end
  if cur_stage < #self.stages then
    if api.nvim_get_current_win() == win then
      return
    end
    self.win_stages[win] = cur_stage + 1
    return
  end

  self.win_stages[win] = nil

  local function close()
    if api.nvim_get_current_win() == win then
      return vim.defer_fn(close, 1000)
    end
    self:_remove_win(win)
  end

  close()
end

function WindowAnimator:_remove_win(win)
  pcall(api.nvim_win_close, win, true)
  self.win_stages[win] = nil
  self.win_states[win] = nil
  self._dirty[win] = nil
  self._needs_flush = true
  self:_stop_timer(win)
  local notif_buf = self.notif_bufs[win]
  self.notif_bufs[win] = nil
  notif_buf:close(win)
end

function WindowAnimator:on_refresh(win)
  local notif_buf = self.notif_bufs[win]
  if not notif_buf then
    return
  end
  self._dirty[win] = true
  local timer = self.timers[win]
  if timer then
    local timeout = self:_timeout_ms(notif_buf)
    if timeout then
      timer:set_repeat(timeout)
      timer:again()
    else
      self:_stop_timer(win)
    end
  end
end

--- A notification's own timeout wins. `true` or no value means the configured default.
---@return integer|false timeout Milliseconds, or false if the notification stays until dismissed
function WindowAnimator:_timeout_ms(notif_buf)
  local timeout = notif_buf:timeout()
  if timeout == nil or timeout == true then
    timeout = self.config.default_timeout()
  end
  return type(timeout) == "number" and timeout
end

function WindowAnimator:_stop_timer(win)
  local timer = self.timers[win]
  if not timer then
    return
  end
  self.timers[win] = nil
  timer:stop()
  if not timer:is_closing() then
    timer:close()
  end
end

function WindowAnimator:_start_timer(win)
  local timeout = self:_timeout_ms(self.notif_bufs[win])
  if not timeout then
    return
  end
  local timer = vim.uv.new_timer()
  self.timers[win] = timer
  timer:start(
    timeout,
    timeout,
    vim.schedule_wrap(function()
      -- The timer may have been stopped while this callback was queued.
      if self.timers[win] ~= timer then
        return
      end
      self:_stop_timer(win)
      local notif_buf = self.notif_bufs[win]
      if not (notif_buf and notif_buf:should_stay()) then
        self:_advance_win_stage(win)
      end
      self:_wake()
    end)
  )
end

---@return boolean settled Whether the window is waiting in its timed stage with nothing to animate
function WindowAnimator:_update_window(time, win, open_windows)
  local stage = self.win_stages[win]
  local notif_buf = self.notif_bufs[win]
  local win_goals = self:_get_win_goals(win, stage, open_windows)

  -- If we don't animate, then we move to all goals instantly.
  -- Can't just jump to the end, because we need to the intermediate changes
  while
    win_goals
    and not notif_buf:should_animate()
    and win_goals.time == nil
    and self.win_stages[win] < #self.stages
  do
    for field, goal in pairs(win_goals) do
      if type(goal) == "table" then
        win_goals[field] = goal[1]
      end
    end
    self:_advance_win_state(win, win_goals, time)
    self:_advance_win_stage(win)
    stage = self.win_stages[win]
    win_goals = self:_get_win_goals(win, stage, open_windows)
  end

  if not win_goals then
    self:_remove_win(win)
    return false
  end

  if win_goals.time and not self.timers[win] then
    self:_start_timer(win)
  end

  local updated = self:_advance_win_state(win, win_goals, time)

  if self:_is_complete(win, win_goals) and not win_goals.time then
    self:_advance_win_stage(win)
  end

  return win_goals.time ~= nil and not updated and self:_reached_goals(win, win_goals)
end

--- Unlike `_is_complete`, ignores `complete` callbacks: stages use those to move on before a spring
--- has come to rest, and a window that is still moving must keep the loop at full speed.
function WindowAnimator:_reached_goals(win, goals)
  local win_state = self.win_states[win]
  if not win_state then
    return false
  end
  for field, goal in pairs(goals) do
    if type(goal) == "table" then
      local state = win_state[field]
      if not state or math.abs(state.position - goal[1]) >= 0.05 then
        return false
      end
    end
  end
  return true
end

function WindowAnimator:_is_complete(win, goals)
  local complete = true
  local win_state = self.win_states[win]
  if not win_state then
    return true
  end
  for field, goal in pairs(goals) do
    if field ~= "time" then
      if type(goal) == "table" then
        if goal.complete then
          complete = goal.complete(win_state[field].position)
        else
          complete = goal[1] == round(win_state[field].position, 2)
        end
      end
      if not complete then
        break
      end
    end
  end
  return complete
end

function WindowAnimator:_advance_win_state(win, goals, time)
  local win_state = self.win_states[win]

  local win_configs = {}

  local function win_conf(win_)
    if win_configs[win_] then
      return win_configs[win_]
    end
    local exists, conf = util.get_win_config(win_)
    if not exists then
      self:_remove_win(win_)
      return
    end
    win_configs[win_] = conf
    return conf
  end

  for field, goal in pairs(goals) do
    if field ~= "time" then
      local goal_type = type(goal)
      -- Handle spring goal
      if goal_type == "table" and goal[1] then
        if not win_state[field] then
          if field == "opacity" then
            win_state[field] = { position = self.notif_bufs[win].highlights:get_opacity() }
          else
            local conf = win_conf(win)
            if not conf then
              return true
            end
            win_state[field] = { position = conf[field] }
          end
        end
        animate.spring(time, goal[1], win_state[field], goal.frequency or 1, goal.damping or 1)
        --- Directly move goal
      elseif goal_type ~= "table" then
        win_state[field] = { position = goal }
      else
        error("nvim-notify: Invalid stage goal: " .. vim.inspect(goal))
      end
    end
  end

  return self:_apply_win_state(win, win_state)
end

function WindowAnimator:_get_win_goals(win, win_stage, open_windows)
  local notif_buf = self.notif_bufs[win]
  local win_goals = self.stages[win_stage]({
    buffer = notif_buf:buffer(),
    message = self:_get_dimensions(notif_buf),
    open_windows = open_windows,
  }, win)
  return win_goals
end

function WindowAnimator:_get_dimensions(notif_buf)
  return {
    height = math.min(self.config.max_height() or 1000, notif_buf:height()),
    width = math.min(self.config.max_width() or 1000, notif_buf:width()),
  }
end

function WindowAnimator:_apply_win_state(win, win_state)
  local hl_updated = false
  if win_state.opacity then
    local notif_buf = self.notif_bufs[win]
    if notif_buf:is_valid() then
      hl_updated = notif_buf.highlights:set_opacity(win_state.opacity.position)
    end
  end
  local exists, conf = util.get_win_config(win)
  local new_conf = {}
  local win_updated = false
  if not exists then
    self:_remove_win(win)
  else
    local function set_field(field, min, round_to)
      if not win_state[field] then
        return
      end
      local new_value = max(round(win_state[field].position, round_to), min)
      if new_value == conf[field] then
        return
      end
      win_updated = true
      new_conf[field] = new_value
    end

    set_field("row", 0, 1)
    set_field("col", 0, 1)
    set_field("width", 1)
    set_field("height", 1)

    if win_updated then
      if new_conf.row or new_conf.col then
        new_conf.relative = conf.relative
        new_conf.row = new_conf.row or conf.row
        new_conf.col = new_conf.col or conf.col
      end
      api.nvim_win_set_config(win, new_conf)
    end
  end

  if hl_updated or win_updated then
    self._dirty[win] = true
  end
  return hl_updated or win_updated
end

---@return WindowAnimator
return function(stages, config)
  return WindowAnimator:new(stages, config)
end
