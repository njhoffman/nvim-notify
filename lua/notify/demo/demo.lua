local log = require("notify.util.log")

local M = { active = false, _token = nil }

local function notify_fn(...)
  return require("notify").notify(...)
end

local function reverse_list(list)
  local reversed = {}
  for i = #list, 1, -1 do
    table.insert(reversed, list[i])
  end
  return reversed
end

function M.run(cfg, on_complete)
  if M.active then
    return false
  end
  M.active = true
  local token = {}
  M._token = token

  local opts = cfg.opts
  local variants = cfg.variants

  log.info("notify demo: starting", { opts = opts, variant_count = vim.tbl_count(variants) })

  local delay = 0

  for _, name in ipairs(reverse_list(vim.tbl_keys(variants))) do
    local variant = variants[name]
    for _, render in ipairs(opts.renders) do
      for _, level in ipairs(opts.levels) do
        local props = { level = level, name = name, render = render }
        local notify_opts = { timeout = opts.notify_timeout, render = props.render }

        if variant.title then
          notify_opts.title = type(variant.title) == "function" and variant.title(props)
            or variant.title
        end

        local default_body = "Rendering " .. name .. " (" .. render .. ") level: " .. level
        local body = type(variant.body) == "function" and variant.body(props)
          or type(variant.body) == "string" and variant.body
          or default_body

        vim.defer_fn(function()
          if M._token == token then
            notify_fn(body, level, notify_opts)
          end
        end, delay)
        delay = delay + opts.delay
      end
      delay = delay + opts.group_timeout
    end
    delay = delay + opts.group_timeout
  end

  vim.defer_fn(function()
    if M._token ~= token then
      return
    end
    M.active = false
    M._token = nil
    log.info("notify demo: completed")
    if on_complete then
      on_complete()
    end
  end, delay + opts.notify_timeout)

  return true
end

function M.stop()
  if not M.active then
    return false
  end
  M.active = false
  M._token = nil
  log.info("notify demo: stopping")
  notify_fn("Notify demo stopped", "warn", { title = "nvim-notify" })
  return true
end

return M
