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
    local notif = notify.async("timed")
    notif.events.open()
    local start = vim.uv.now()
    notif.events.close()
    vim.uv.update_time()
    assert.is_true(vim.uv.now() - start < 600 + REACTION_MS)
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

describe("notification timeouts", function()
  local notify = require("notify")
  local real_print = _G.print
  local printed

  local function setup(extra)
    notify.setup(vim.tbl_extend("force", {
      background_colour = "#000000",
      stages = "static",
      fps = 30,
    }, extra or {}))
  end

  before_each(function()
    printed = {}
    _G.print = function(...)
      table.insert(printed, table.concat(vim.tbl_map(tostring, { ... }), " "))
    end
  end)

  after_each(function()
    _G.print = real_print
    notify.dismiss({ pending = true, silent = true })
  end)

  a.it("keeps a notification open when the configured timeout is false", function()
    setup({ timeout = false })
    local win = notify.async("forever").events.open()
    a.util.sleep(200)
    a.util.scheduler()
    assert.same({}, printed)
    assert.is.True(vim.api.nvim_win_is_valid(win))
  end)

  a.it("replaces a notification when the configured timeout is false", function()
    setup({ timeout = false })
    local record = notify.async("before")
    local win = record.events.open()
    a.util.sleep(100)
    notify.notify("after", "info", { replace = record })
    a.util.sleep(100)
    a.util.scheduler()
    assert.same({}, printed)
    assert.is.True(vim.api.nvim_win_is_valid(win))
  end)

  a.it("uses a notification's own timeout over a false default", function()
    setup({ timeout = false })
    local closed = false
    notify.notify("short", "info", {
      timeout = 100,
      on_close = function()
        closed = true
      end,
    })
    a.util.sleep(400)
    assert.is.True(closed)
  end)

  a.it("treats timeout = true as the configured default", function()
    setup({ timeout = 100 })
    local closed = false
    notify.notify("default", "info", {
      timeout = true,
      on_close = function()
        closed = true
      end,
    })
    a.util.sleep(400)
    assert.same({}, printed)
    assert.is.True(closed)
  end)

  a.it("stays open when timeout = true and the configured default is false", function()
    setup({ timeout = false })
    local win = notify.async("forever", "info", { timeout = true }).events.open()
    a.util.sleep(200)
    a.util.scheduler()
    assert.same({}, printed)
    assert.is.True(vim.api.nvim_win_is_valid(win))
  end)

  a.it("stays open when the configured timeout is true", function()
    setup({ timeout = true })
    local win = notify.async("forever").events.open()
    a.util.sleep(200)
    a.util.scheduler()
    assert.same({}, printed)
    assert.is.True(vim.api.nvim_win_is_valid(win))
  end)

  a.it("cancels the timer when replaced with timeout = false", function()
    setup({ timeout = 300 })
    local record = notify.async("timed")
    local win = record.events.open()
    a.util.sleep(50)
    notify.notify("forever", "info", { replace = record, timeout = false })
    a.util.sleep(500)
    a.util.scheduler()
    assert.same({}, printed)
    assert.is.True(vim.api.nvim_win_is_valid(win))
  end)

  describe("timer handles", function()
    local real_new_timer = vim.uv.new_timer
    local timers

    before_each(function()
      timers = {}
      vim.uv.new_timer = function()
        local timer = real_new_timer()
        table.insert(timers, timer)
        return timer
      end
    end)

    after_each(function()
      vim.uv.new_timer = real_new_timer
    end)

    a.it("ignores a callback already queued when its timer was cancelled", function()
      local TIMEOUT = 1000000
      local callback
      -- Forwards to a real timer, because vim.defer_fn and plenary's sleep use new_timer as well.
      vim.uv.new_timer = function()
        local timer = real_new_timer()
        return setmetatable({}, {
          __index = function(_, method)
            return function(_, first, second, fn)
              if method == "start" and first == TIMEOUT then
                callback = fn
              end
              return timer[method](timer, first, second, fn)
            end
          end,
        })
      end
      setup({ timeout = TIMEOUT })
      local record = notify.async("timed")
      local win = record.events.open()
      a.util.sleep(50)
      assert.is_not_nil(callback)
      notify.notify("forever", "info", { replace = record, timeout = false })
      callback()
      a.util.sleep(100)
      a.util.scheduler()
      assert.same({}, printed)
      assert.is.True(vim.api.nvim_win_is_valid(win))
    end)

    a.it("closes the timer when it fires", function()
      setup({ timeout = 100 })
      local notif = notify.async("timed")
      notif.events.open()
      notif.events.close()
      local window_timers = 0
      for _, timer in ipairs(timers) do
        if timer:is_closing() then
          window_timers = window_timers + 1
        end
      end
      assert.is_true(window_timers >= 1)
    end)

    a.it("closes the timer of a dismissed notification", function()
      setup({ timeout = 1000000 })
      local closed = false
      notify.notify("held", "info", {
        on_close = function()
          closed = true
        end,
      })
      a.util.sleep(100)
      local started = vim.deepcopy(#timers)
      assert.is_true(started >= 1)
      notify.dismiss({ pending = true, silent = true })
      a.util.sleep(100)
      a.util.scheduler()
      assert.is.True(closed)
      for _, timer in ipairs(timers) do
        if timer:get_due_in() > 100000 then
          assert.is.True(timer:is_closing())
        end
      end
    end)
  end)
end)

describe("stages returning nil", function()
  local notify = require("notify")
  local real_print = _G.print

  after_each(function()
    _G.print = real_print
    notify.dismiss({ pending = true, silent = true })
  end)

  a.it("removes the window and keeps the loop running", function()
    local printed = {}
    _G.print = function(...)
      table.insert(printed, tostring((...)))
    end
    local stages = hold_stages()
    stages[2] = function()
      return nil
    end
    notify.setup({ background_colour = "#000000", stages = stages, timeout = 1000000 })
    local closed = false
    local win
    notify.notify("gone", "info", {
      on_open = function(opened)
        win = opened
      end,
      on_close = function()
        closed = true
      end,
    })
    a.util.sleep(100)
    a.util.scheduler()
    assert.same({}, printed)
    assert.is.False(vim.api.nvim_win_is_valid(win))
    assert.is.True(closed)
  end)

  a.it("removes a window whose later stage is nil without animating", function()
    local printed = {}
    _G.print = function(...)
      table.insert(printed, tostring((...)))
    end
    local stages = hold_stages()
    stages[2] = function()
      return {}
    end
    stages[3] = function()
      return nil
    end
    stages[4] = function()
      return {}
    end
    notify.setup({ background_colour = "#000000", stages = stages, timeout = 1000000 })
    local closed = false
    notify.notify("gone", "info", {
      animate = false,
      on_close = function()
        closed = true
      end,
    })
    a.util.sleep(100)
    a.util.scheduler()
    assert.same({}, printed)
    assert.is.True(closed)
  end)
end)

describe("fade length", function()
  local notify = require("notify")
  local animator_class_timer = animator_class._start_timer

  after_each(function()
    animator_class._start_timer = animator_class_timer
    notify.dismiss({ pending = true, silent = true })
  end)

  local function setup(stages)
    vim.api.nvim_set_hl(0, "NotifyINFOBody", { fg = "#ffffff" })
    notify.setup({ background_colour = "#000000", stages = stages, timeout = 1000000 })
  end

  --- Milliseconds from sending a notification until it reaches its timed stage.
  local function time_to_hold()
    local reached = false
    animator_class._start_timer = function(...)
      reached = true
      return animator_class_timer(...)
    end
    local start = vim.uv.hrtime()
    local win = notify.async("fading").events.open()
    vim.wait(5000, function()
      return reached
    end, 10)
    return (vim.uv.hrtime() - start) / 1e6, win
  end

  a.it("reaches the timed stage once the colours have stopped changing", function()
    setup("fade")
    local elapsed = time_to_hold()
    -- The whole spring takes about 2 s, and its visible part about 1.35 s.
    assert.is_true(elapsed > 1000, "too fast: " .. elapsed)
    assert.is_true(elapsed < 1700, "too slow: " .. elapsed)
  end)

  a.it("ends on the exact colour", function()
    setup("fade")
    local _, win = time_to_hold()
    a.util.sleep(100)
    a.util.scheduler()
    local buf = vim.api.nvim_win_get_buf(win)
    local ns = vim.api.nvim_get_hl_ns({ winid = win })
    local body = vim.api.nvim_get_hl(ns, { name = "NotifyINFOBody" .. buf })
    assert.equals(0xffffff, body.fg)
  end)

  a.it("is not lengthened by a blocked main loop", function()
    setup("fade")
    local reached = false
    animator_class._start_timer = function(...)
      reached = true
      return animator_class_timer(...)
    end
    local start = vim.uv.hrtime()
    notify.notify("stalled")
    -- Three stalls of 200 ms, under the step limit. Counting frames would add all 600 ms.
    for _ = 1, 3 do
      a.util.sleep(100)
      a.util.scheduler()
      vim.uv.sleep(200)
    end
    a.util.scheduler()
    vim.wait(5000, function()
      return reached
    end, 10)
    local elapsed = (vim.uv.hrtime() - start) / 1e6
    assert.is_true(elapsed < 1750, "took " .. elapsed)
  end)

  a.it("lands on exactly full opacity", function()
    local highlights_class =
      getmetatable(require("notify.service.buffer.highlights")({ level = "INFO" }, 0, {
        background_colour = function()
          return 0
        end,
      }))
    local real_set_opacity = highlights_class.set_opacity
    local last
    highlights_class.set_opacity = function(self, alpha)
      last = alpha
      return real_set_opacity(self, alpha)
    end
    setup("fade")
    time_to_hold()
    a.util.sleep(100)
    a.util.scheduler()
    highlights_class.set_opacity = real_set_opacity
    assert.equals(100, last)
  end)

  a.it("still honours a stage's own complete callback", function()
    local stages = hold_stages()
    local hold = stages[2]
    local passed = false
    stages[2] = function()
      return {
        opacity = {
          100,
          complete = function(position)
            if position >= 99.9999 then
              passed = true
            end
            return passed
          end,
        },
      }
    end
    stages[3] = hold
    stages[4] = function()
      return {}
    end
    setup(stages)
    local start = vim.uv.hrtime()
    local reached = false
    animator_class._start_timer = function(...)
      reached = true
      return animator_class_timer(...)
    end
    notify.notify("custom")
    vim.wait(5000, function()
      return reached
    end, 10)
    assert.is_true((vim.uv.hrtime() - start) / 1e6 > 1800)
  end)

  a.it("does not settle other goals early", function()
    local stages = hold_stages()
    local hold = stages[2]
    stages[2] = function()
      return { row = { 10, frequency = 1 } }
    end
    stages[3] = hold
    stages[4] = function()
      return {}
    end
    setup(stages)
    local reached = false
    animator_class._start_timer = function(...)
      reached = true
      return animator_class_timer(...)
    end
    local start = vim.uv.hrtime()
    notify.notify("custom")
    vim.wait(5000, function()
      return reached
    end, 10)
    -- Within 0.2 of 10 comes at about 0.95 s, and the exact goal at about 1.6 s.
    assert.is_true((vim.uv.hrtime() - start) / 1e6 > 1300)
  end)
end)

describe("notify.async callbacks", function()
  local notify = require("notify")

  before_each(function()
    notify.setup({ background_colour = "#000000", stages = "static", timeout = 100 })
  end)

  after_each(function()
    notify.dismiss({ pending = true, silent = true })
  end)

  a.it("runs the caller's callbacks and still resolves its events", function()
    local opened, closed
    local notif = notify.async("both", "info", {
      on_open = function(win)
        opened = win
      end,
      on_close = function(win)
        closed = win
      end,
    })
    local win = notif.events.open()
    assert.equals(win, opened)
    assert.equals(win, notif.events.close())
    assert.equals(win, closed)
  end)

  a.it("resolves its events without caller callbacks", function()
    local notif = notify.async("plain")
    local win = notif.events.open()
    assert.equals(win, notif.events.close())
  end)

  a.it("does not change the caller's options", function()
    local on_close = function() end
    local opts = { on_close = on_close }
    local notif = notify.async("opts", "info", opts)
    notif.events.open()
    assert.equals(on_close, opts.on_close)
    assert.is_nil(opts.on_open)
  end)

  a.it("resolves close when the caller's on_close fails", function()
    local notif = notify.async("failing", "info", {
      on_close = function()
        error("caller bug")
      end,
    })
    notif.events.open()
    assert.is_number(notif.events.close())
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

  describe("frame time", function()
    local real_hrtime = vim.uv.hrtime
    local now, steps, service

    before_each(function()
      now, steps = 0, {}
      vim.uv.hrtime = function()
        return now
      end
      service = settled_service()
      service._animator.render = function(_, _, time)
        table.insert(steps, time)
        return true, false
      end
    end)

    after_each(function()
      vim.uv.hrtime = real_hrtime
    end)

    local function close_to(expected, actual)
      assert.is_true(math.abs(expected - actual) < 1e-6, tostring(actual))
    end

    local function frame_after(seconds)
      now = now + seconds * 1e9
      service:_run()
    end

    it("uses the frame rate for the first frame", function()
      service:_run()
      close_to(1 / 30, steps[1])
    end)

    it("uses the time that passed for later frames", function()
      service:_run()
      frame_after(0.1)
      close_to(0.1, steps[2])
    end)

    it("limits the step after a long stall", function()
      service:_run()
      frame_after(5)
      close_to(0.25, steps[2])
    end)

    it("starts again from the frame rate after settling", function()
      service:_run()
      service._animator.render = function(_, _, time)
        table.insert(steps, time)
        return true, true
      end
      frame_after(0.05)
      frame_after(0.5)
      close_to(1 / 30, steps[3])
    end)

    it("starts again from the frame rate after the loop stops", function()
      service:_run()
      service._animator.render = function()
        return false, false
      end
      frame_after(0.05)
      service._animator.render = function(_, _, time)
        table.insert(steps, time)
        return true, false
      end
      frame_after(60)
      close_to(1 / 30, steps[#steps])
    end)
  end)

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
