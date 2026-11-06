local util = require("notify.util")
local NotificationBuf = require("notify.service.buffer")

---@class NotificationService
---@field private _config notify.ServiceConfig
---@field private _running boolean
---@field private _pending FIFOQueue
---@field private _animator WindowAnimator
---@field private _buffers table<integer, NotificationBuf>
---@field private _fps integer
---@field private _next_run table|nil Identifies the scheduled run, a stale one must not fire
---@field private _sleeping uv.uv_timer_t|nil Timer of the scheduled run while settled
local NotificationService = {}

-- How often the loop runs while every window is settled. Timers, new notifications, replacements,
-- closed windows and resizes wake it immediately; this catches what they cannot, such as stages
-- with goals that change over time or windows closed with :noautocmd.
local SETTLED_INTERVAL_MS = 500

---@class notify.ServiceConfig
---@field fps integer

---@param config notify.ServiceConfig
function NotificationService:new(config, animator)
  local service = {
    _config = config,
    _fps = config.fps(),
    _animator = animator,
    _pending = util.FIFOQueue(),
    _running = false,
    _buffers = {},
  }
  self.__index = self
  setmetatable(service, self)
  animator.on_wake = function()
    service:_wake()
  end
  return service
end

function NotificationService:_create_autocmds()
  if self._autocmds_created then
    return
  end
  self._autocmds_created = true
  local group = vim.api.nvim_create_augroup("nvim-notify-service", { clear = false })
  local function wake()
    vim.schedule(function()
      self:_wake()
    end)
  end
  vim.api.nvim_create_autocmd("VimResized", { group = group, callback = wake })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      if self._animator.win_stages[tonumber(args.match)] then
        wake()
      end
    end,
  })
end

--- Run the next frame now if the loop is waiting out a settled interval.
function NotificationService:_wake()
  local timer = self._sleeping
  if not timer then
    return
  end
  self._sleeping = nil
  self._next_run = nil
  if not timer:is_closing() then
    timer:stop()
    timer:close()
  end
  self:_run()
end

function NotificationService:_run()
  self._running = true
  self:_create_autocmds()
  local succees, updated, settled =
    pcall(self._animator.render, self._animator, self._pending, 1 / self._fps)
  if not succees then
    print("Error running notification service: " .. updated)
    self._running = false
    return
  end
  if not updated then
    self._running = false
    return
  end
  local run = {}
  self._next_run = run
  local timer = vim.defer_fn(function()
    -- A woken loop may have already replaced this run while its callback was queued.
    if self._next_run == run then
      self._sleeping = nil
      self:_run()
    end
  end, settled and SETTLED_INTERVAL_MS or 1000 / self._fps)
  self._sleeping = settled and timer or nil
end

---@param notif notify.Notification;q
---@return integer
function NotificationService:push(notif)
  local buf = vim.api.nvim_create_buf(false, true)
  local notif_buf = NotificationBuf(buf, notif, { config = self._config })
  notif_buf:render()
  self._buffers[notif.id] = notif_buf
  self._pending:push(notif_buf)

  if not self._running then
    self:_run()
  else
    self:_wake()
  end
  return buf
end

function NotificationService:replace(id, notif)
  local existing = self._buffers[id]
  if not (existing and existing:is_valid()) then
    vim.notify(
      "No matching notification found to replace id: "
        .. vim.inspect(id)
        .. "\n"
        .. vim.inspect(vim.tbl_keys(self._buffers)),
      0
    )
    return
  end
  local prev = vim.deepcopy(existing)
  existing:set_notification(notif)
  self._buffers[id] = nil
  self._buffers[notif.id] = existing
  pcall(existing.render, existing)

  local win = vim.fn.bufwinid(existing:buffer())
  if notif.on_replace then
    notif.on_replace(win, prev, existing)
  end
  if self._config.on_replace() then
    self._config.on_replace()(win, prev, existing)
  end

  if win ~= -1 then
    -- Highlights can change name if level changed so we have to re-link
    -- vim.wo does not behave like setlocal, thus we use setwinvar to set a
    -- local option. Otherwise our changes would affect subsequently opened
    -- windows.
    -- see e.g. neovim#14595
    vim.fn.setwinvar(
      win,
      "&winhl",
      "NormalNC:NONE"
        .. ",Normal:"
        .. existing.highlights.body
        .. ",FloatBorder:"
        .. existing.highlights.border
    )

    vim.api.nvim_set_option_value("cursorcolumn", false, { win = win })
    vim.api.nvim_set_option_value("cursorline", false, { win = win })
    -- vim.api.nvim_win_set_width(win, existing:width())
    -- vim.api.nvim_win_set_height(win, existing:height())
    existing.highlights:attach(win)
    self._animator:on_refresh(win)
    self:_wake()
  end
end

function NotificationService:dismiss(opts)
  local notif_wins = vim.tbl_keys(self._animator.win_stages)
  for _, win in pairs(notif_wins) do
    pcall(vim.api.nvim_win_close, win, true)
  end
  if opts.pending then
    local cleared = 0
    while self._pending:pop() do
      cleared = cleared + 1
    end
    if not opts.silent then
      vim.notify("Cleared " .. cleared .. " pending notifications")
    end
  end
end

function NotificationService:pending()
  return self._pending:length()
end

---@return NotificationService
return function(config, animator)
  return NotificationService:new(config, animator)
end
