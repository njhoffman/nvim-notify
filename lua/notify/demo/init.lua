---@tag notify.demo
---@text
--- Interactive demo for nvim-notify.
---
--- Invoke via |:NotificationsDemo|. The first invocation opens a scratch
--- buffer pre-filled with the default options. Edit the buffer and press
--- `<CR>` (normal mode) to launch the demo with those options, or `q` to
--- dismiss without running.
---
--- The buffer must evaluate to a table of the form:
--- >lua
---     return {
---       opts = {
---         delay = 200,
---         notify_timeout = 3000,
---         group_timeout = 4000,
---         levels = { "trace", "debug", "info", "warn", "error" },
---         stages = "fade_in_slide_out",
---         renders = { "minimal", "simple", "compact", "default",
---                     "wrapped-minimal", "wrapped-compact", "wrapped-default" },
---       },
---       variants = require("notify.demo.variants"),
---     }
--- <

local log = require("notify.util.log")

local M = {}

local SCRATCH_NAME = "notify-demo-options"

local default_opts = {
  delay = 200,
  notify_timeout = 3000,
  group_timeout = 4000,
  levels = { "trace", "debug", "info", "warn", "error" },
  stages = "fade_in_slide_out",
  renders = {
    "minimal",
    "simple",
    "compact",
    "default",
    "wrapped-minimal",
    "wrapped-compact",
    "wrapped-default",
  },
}

local SCRATCH_TEMPLATE = [[
-- nvim-notify demo options
--
-- Edit this buffer, then press <CR> in normal mode to run the demo.
-- Press q to dismiss without running.
--
-- `opts` controls timing and which levels/renderers are cycled.
-- `variants` is a map of variant name -> { body, title } where body/title can
-- be strings or functions receiving { level, name, render }.

return {
  opts = {
    delay = 200,
    notify_timeout = 3000,
    group_timeout = 4000,
    levels = { "trace", "debug", "info", "warn", "error" },
    stages = "fade_in_slide_out",
    renders = {
      "minimal",
      "simple",
      "compact",
      "default",
      "wrapped-minimal",
      "wrapped-compact",
      "wrapped-default",
    },
  },

  variants = require("notify.demo.variants"),
}
]]

--- Merge user overrides over the built-in defaults.
---@param user_variants table|nil
---@param user_opts table|nil
---@return table cfg `{ opts = ..., variants = ... }`
function M.get_config(user_variants, user_opts)
  return {
    opts = vim.tbl_extend("force", vim.deepcopy(default_opts), user_opts or {}),
    variants = user_variants or require("notify.demo.variants"),
  }
end

--- Render the default template as lines for a scratch buffer.
---@return string[]
function M.template_lines()
  return vim.split(SCRATCH_TEMPLATE, "\n", { plain = true })
end

local function find_scratch()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local ok, marker = pcall(vim.api.nvim_buf_get_var, bufnr, "notify_demo_scratch")
      if ok and marker then
        return bufnr
      end
    end
  end
  return nil
end

--- Open (or focus) a scratch buffer holding editable demo options.
---@return integer bufnr
function M.open_scratch()
  local existing = find_scratch()
  if existing then
    local win = vim.fn.bufwinid(existing)
    if win ~= -1 then
      vim.api.nvim_set_current_win(win)
    else
      vim.api.nvim_set_current_buf(existing)
    end
    return existing
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, M.template_lines())
  vim.api.nvim_buf_set_var(bufnr, "notify_demo_scratch", true)
  vim.api.nvim_buf_set_name(bufnr, SCRATCH_NAME)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
  vim.api.nvim_set_option_value("swapfile", false, { buf = bufnr })
  vim.api.nvim_set_option_value("filetype", "lua", { buf = bufnr })

  local keymap_opts = { buffer = bufnr, silent = true, nowait = true }
  vim.keymap.set("n", "<CR>", function()
    M.run_from_buffer(bufnr)
  end, vim.tbl_extend("force", keymap_opts, { desc = "nvim-notify: run demo" }))
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end, vim.tbl_extend("force", keymap_opts, { desc = "nvim-notify: close demo options" }))

  vim.api.nvim_set_current_buf(bufnr)
  return bufnr
end

--- Evaluate buffer contents and return the resulting table.
---@param bufnr integer
---@return boolean ok, table|string result
function M.parse_buffer(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local src = table.concat(lines, "\n")
  local chunk, compile_err = loadstring(src, "notify-demo-options")
  if not chunk then
    return false, compile_err or "compile error"
  end
  local ok, result = pcall(chunk)
  if not ok then
    return false, tostring(result)
  end
  if type(result) ~= "table" then
    return false, "demo config must return a table, got " .. type(result)
  end
  return true, result
end

local RUN_CMD = "NotificationsDemo"
local STOP_CMD = "NotificationsDemoStop"

local function del_cmd(name)
  pcall(vim.api.nvim_del_user_command, name)
end

local function install_run_cmd()
  del_cmd(STOP_CMD)
  del_cmd(RUN_CMD)
  vim.api.nvim_create_user_command(RUN_CMD, function()
    M.setup()
  end, { desc = "nvim-notify: open the demo options buffer" })
end

local function install_stop_cmd()
  del_cmd(RUN_CMD)
  del_cmd(STOP_CMD)
  vim.api.nvim_create_user_command(STOP_CMD, function()
    M.stop()
  end, { desc = "nvim-notify: stop the running demo" })
end

--- Register the `:NotificationsDemo` command. Called from `notify.setup()`.
--- `:NotificationsDemoStop` replaces it while a demo is running and is
--- swapped back when the demo completes or is stopped.
function M.register_commands()
  install_run_cmd()
end

--- Parse the buffer, merge with defaults, and run the demo.
---@param bufnr integer
---@return boolean ok
function M.run_from_buffer(bufnr)
  local ok, result = M.parse_buffer(bufnr)
  if not ok then
    log.error("notify demo: invalid config buffer: " .. tostring(result))
    vim.notify(
      "nvim-notify demo: invalid config\n" .. tostring(result),
      vim.log.levels.ERROR,
      { title = "nvim-notify" }
    )
    return false
  end

  local cfg = M.get_config(result.variants, result.opts)

  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end

  install_stop_cmd()
  local started = require("notify.demo.demo").run(cfg, install_run_cmd)
  if not started then
    install_run_cmd()
    return false
  end
  return true
end

--- Entry point invoked by `:NotificationsDemo`. Opens the scratch buffer.
function M.setup()
  M.open_scratch()
end

--- Stop an in-progress demo and restore `:NotificationsDemo`.
function M.stop()
  local stopped = require("notify.demo.demo").stop()
  if stopped then
    install_run_cmd()
  end
end

return M
