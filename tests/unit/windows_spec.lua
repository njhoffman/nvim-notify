local async = require("plenary.async")
async.tests.add_to_env()
vim.opt.termguicolors = true

local NotifyBufHighlights = require("notify.service.buffer.highlights")
local animator_class = getmetatable(require("notify.windows")({}, {}))

local function fake_config()
  return {
    background_colour = function()
      return 0
    end,
  }
end

local function hold_stages(extra_goals)
  return {
    function(state)
      return {
        relative = "editor",
        anchor = "NE",
        width = state.message.width,
        height = state.message.height,
        col = vim.o.columns,
        row = #state.open_windows * 5,
        border = "rounded",
        style = "minimal",
      }
    end,
    function(state, win)
      local goals = {
        time = true,
        col = { vim.o.columns },
        row = {
          require("notify.stages.util").slot_after_previous(win, state.open_windows, "top_down"),
          frequency = 5,
        },
      }
      return vim.tbl_extend("force", goals, extra_goals and extra_goals() or {})
    end,
    function()
      return { col = { vim.o.columns } }
    end,
  }
end

describe("window highlights", function()
  local buf, hl

  before_each(function()
    vim.api.nvim_set_hl(0, "NotifyINFOBody", { fg = "#ffffff" })
    buf = vim.api.nvim_create_buf(false, true)
    hl = NotifyBufHighlights({ level = "INFO" }, buf, fake_config())
    vim.api.nvim_set_option_value("filetype", "notify", { buf = buf })
  end)

  after_each(function()
    hl:clear()
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("fades in its own namespace and leaves the global group alone", function()
    local global_before = vim.api.nvim_get_hl(0, { name = hl.body })
    assert.is.True(hl:set_opacity(50))
    assert.same(global_before, vim.api.nvim_get_hl(0, { name = hl.body }))
    assert.equals(0x808080, vim.api.nvim_get_hl(hl.namespace, { name = hl.body }).fg)
  end)

  it("does not write colours again when they would not change", function()
    hl:set_opacity(50)
    assert.is.False(hl:set_opacity(50))
    assert.is.False(hl:set_opacity(50.0001))
  end)

  it("reaches the exact colour at full opacity", function()
    hl:set_opacity(99)
    assert.is.True(hl:set_opacity(100))
    assert.equals(0xffffff, vim.api.nvim_get_hl(hl.namespace, { name = hl.body }).fg)
  end)

  it("gives two notifications different namespaces", function()
    local other_buf = vim.api.nvim_create_buf(false, true)
    local other = NotifyBufHighlights({ level = "INFO" }, other_buf, fake_config())
    vim.api.nvim_set_option_value("filetype", "notify", { buf = other_buf })
    hl:set_opacity(50)
    other:set_opacity(50)
    assert.are_not.equal(hl.namespace, other.namespace)
    other:clear()
    vim.api.nvim_buf_delete(other_buf, { force = true })
  end)

  it("recycles the namespace after clear", function()
    hl:set_opacity(50)
    local ns = hl.namespace
    hl:clear()
    assert.is_nil(hl.namespace)

    local other_buf = vim.api.nvim_create_buf(false, true)
    local other = NotifyBufHighlights({ level = "INFO" }, other_buf, fake_config())
    vim.api.nvim_set_option_value("filetype", "notify", { buf = other_buf })
    other:set_opacity(50)
    assert.equals(ns, other.namespace)
    other:clear()
    vim.api.nvim_buf_delete(other_buf, { force = true })
  end)

  it("does not take a namespace after clear", function()
    hl:clear()
    assert.is.False(hl:set_opacity(50))
    assert.is_nil(hl.namespace)
  end)

  it("applies the namespace to the window showing the buffer", function()
    local win = vim.api.nvim_open_win(buf, false, {
      relative = "editor",
      row = 0,
      col = 0,
      width = 5,
      height = 1,
    })
    hl:set_opacity(50)
    assert.equals(hl.namespace, vim.api.nvim_get_hl_ns({ winid = win }))
    vim.api.nvim_win_close(win, true)
  end)
end)

describe("render loop", function()
  local notify = require("notify")
  local real_render = animator_class.render
  local real_redraw = vim.api.nvim__redraw
  local renders, flushes

  -- Long enough to count a few settled ticks, short enough to tell them from frames at 30 fps.
  local QUIET_MS = 700
  local MAX_QUIET_RENDERS = 3
  -- Well below the settled interval, so only a wake-up can explain a reaction this fast.
  local REACTION_MS = 200
  local NEVER_MS = 1000000

  local function setup(extra)
    notify.setup(vim.tbl_extend("force", {
      background_colour = "#000000",
      stages = hold_stages(),
      timeout = NEVER_MS,
      fps = 30,
    }, extra or {}))
  end

  local function settle()
    a.util.sleep(400)
    a.util.scheduler()
  end

  local function renders_during(ms)
    local before = renders
    a.util.sleep(ms)
    a.util.scheduler()
    return renders - before
  end

  before_each(function()
    renders, flushes = 0, 0
    animator_class.render = function(...)
      renders = renders + 1
      return real_render(...)
    end
    vim.api.nvim__redraw = function(opts)
      if opts.flush then
        flushes = flushes + 1
      end
      return real_redraw(opts)
    end
  end)

  after_each(function()
    notify.dismiss({ pending = true, silent = true })
    animator_class.render = real_render
    vim.api.nvim__redraw = real_redraw
  end)

  a.it("slows down once every window is settled", function()
    setup()
    notify.async("settled").events.open()
    settle()
    assert.is_true(renders_during(QUIET_MS) <= MAX_QUIET_RENDERS)
  end)

  a.it("slows down for a notification with no timeout", function()
    setup()
    notify.async("forever", "info", { timeout = false }).events.open()
    settle()
    assert.is_true(renders_during(QUIET_MS) <= MAX_QUIET_RENDERS)
  end)

  a.it("does not flush while settled", function()
    setup()
    notify.async("settled").events.open()
    settle()
    local before = flushes
    a.util.sleep(QUIET_MS)
    a.util.scheduler()
    assert.equals(before, flushes)
  end)

  a.it("flushes a window that opens with nothing to animate", function()
    notify.setup({
      background_colour = "#000000",
      timeout = NEVER_MS,
      stages = {
        function(state)
          return {
            relative = "editor",
            width = state.message.width,
            height = state.message.height,
            row = 0,
            col = 0,
            style = "minimal",
          }
        end,
        function()
          return { time = true }
        end,
        function()
          return {}
        end,
      },
    })
    local before = flushes
    notify.notify("still")
    assert.equals(before + 1, flushes)
  end)

  a.it("flushes when a window closes", function()
    setup({ timeout = 100 })
    local notif = notify.async("short")
    notif.events.open()
    local before = flushes
    notif.events.close()
    a.util.sleep(50)
    assert.is_true(flushes > before)
  end)

  a.it("stays at full speed while a window is still moving", function()
    setup()
    notify.setup({
      background_colour = "#000000",
      timeout = NEVER_MS,
      fps = 30,
      stages = hold_stages(function()
        return { row = { 25, frequency = 0.05 } }
      end),
    })
    notify.async("slow").events.open()
    a.util.sleep(50)
    assert.is_true(renders_during(QUIET_MS) > 10)
  end)

  a.it("opens a new notification immediately while settled", function()
    setup()
    notify.async("first").events.open()
    settle()
    local before = #vim.api.nvim_list_wins()
    notify.notify("second")
    assert.equals(before + 1, #vim.api.nvim_list_wins())
  end)

  a.it("closes a timed notification without waiting for the settled interval", function()
    setup({ timeout = 600 })
    local start
    local closed_at
    local notif = notify.async("timed", "info", {
      on_close = function()
        closed_at = vim.uv.now()
      end,
    })
    notif.events.open()
    start = vim.uv.now()
    notif.events.close()
    a.util.scheduler()
    vim.uv.update_time()
    closed_at = closed_at or vim.uv.now()
    assert.is_true(closed_at - start < 600 + REACTION_MS)
  end)

  a.it("keeps a notification open and rearms its timer when keep is true", function()
    setup({ timeout = 100 })
    local keep = true
    local closed = false
    notify.notify("kept", "info", {
      keep = function()
        return keep
      end,
      on_close = function()
        closed = true
      end,
    })
    a.util.sleep(400)
    assert.is.False(closed)
    keep = false
    a.util.sleep(400)
    assert.is.True(closed)
  end)

  a.it("moves other windows up as soon as one is closed", function()
    setup()
    local first = notify.async("first").events.open()
    local second = notify.async("second").events.open()
    settle()
    local row_before = vim.api.nvim_win_get_config(second).row
    local before = renders
    vim.api.nvim_win_close(first, true)
    -- One scheduler turn is far shorter than the settled interval, so only a wake-up renders here.
    a.util.scheduler()
    assert.is_true(renders > before)
    a.util.sleep(REACTION_MS)
    a.util.scheduler()
    assert.is_true(vim.api.nvim_win_get_config(second).row < row_before)
  end)

  a.it("follows a resize while settled", function()
    setup()
    local win = notify.async("resize").events.open()
    settle()
    local columns = vim.o.columns
    local before = renders
    vim.o.columns = columns - 10
    vim.cmd("doautocmd VimResized")
    -- One scheduler turn is far shorter than the settled interval, so only a wake-up renders here.
    a.util.scheduler()
    local woken = renders > before
    a.util.sleep(100)
    a.util.scheduler()
    local col = vim.api.nvim_win_get_config(win).col
    vim.o.columns = columns
    assert.is.True(woken)
    assert.is_true(col < columns)
  end)

  a.it("flushes a replacement immediately while settled", function()
    setup()
    local record = notify.async("before")
    record.events.open()
    settle()
    local before = flushes
    notify.notify("after", "info", { replace = record })
    assert.is_true(flushes > before)
  end)

  a.it("picks up stage goals that change while settled", function()
    local target = 0
    notify.setup({
      background_colour = "#000000",
      timeout = NEVER_MS,
      fps = 30,
      stages = hold_stages(function()
        return { row = { target, frequency = 5 } }
      end),
    })
    local win = notify.async("dynamic").events.open()
    settle()
    target = 10
    a.util.sleep(1000)
    a.util.scheduler()
    assert.is_true(math.abs(vim.api.nvim_win_get_config(win).row - 10) < 1)
  end)

  a.it("does not start a second loop when woken repeatedly", function()
    setup()
    notify.async("first").events.open()
    settle()
    for i = 1, 5 do
      notify.notify("wake " .. i)
      a.util.sleep(5)
    end
    settle()
    assert.is_true(renders_during(QUIET_MS) <= MAX_QUIET_RENDERS)
  end)
end)

describe("notification service wake", function()
  local NotificationService = require("notify.service")
  local real_defer_fn = vim.defer_fn
  local scheduled

  local function fake_timer()
    local closing = false
    return {
      is_closing = function()
        return closing
      end,
      stop = function() end,
      close = function()
        closing = true
      end,
    }
  end

  before_each(function()
    scheduled = {}
    vim.defer_fn = function(fn, delay)
      table.insert(scheduled, { fn = fn, delay = delay })
      return fake_timer()
    end
  end)

  after_each(function()
    vim.defer_fn = real_defer_fn
  end)

  local function settled_service()
    local animator = {
      win_stages = {},
      render = function()
        return true, true
      end,
    }
    return NotificationService({
      fps = function()
        return 30
      end,
    }, animator)
  end

  it("ignores a run that was already queued when it woke", function()
    local service = settled_service()
    service:_run()
    assert.equals(1, #scheduled)

    service:_wake()
    assert.equals(2, #scheduled)

    scheduled[1].fn()
    assert.equals(2, #scheduled)

    scheduled[2].fn()
    assert.equals(3, #scheduled)
  end)

  it("does nothing when woken at full speed", function()
    local service = settled_service()
    service._animator.render = function()
      return true, false
    end
    service:_run()
    service:_wake()
    assert.equals(1, #scheduled)
  end)

  it("waits longer between runs while settled", function()
    local service = settled_service()
    service:_run()
    local settled_delay = scheduled[1].delay
    service._animator.render = function()
      return true, false
    end
    scheduled[1].fn()
    assert.is_true(settled_delay > scheduled[2].delay)
  end)
end)
