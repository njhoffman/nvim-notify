local async = require("plenary.async")
async.tests.add_to_env()
vim.opt.termguicolors = true
A = vim.schedule_wrap(function(...)
  print(vim.inspect(...))
end)

describe("checking public interface", function()
  local notify = require("notify")
  local async_notify = require("notify").async
  assert:add_formatter(vim.inspect)

  before_each(function()
    notify.setup({ background_colour = "#000000" })
    notify.dismiss({ pending = true, silent = true })
  end)

  describe("notifications", function()
    it("returns all previous notifications", function()
      notify.notify("test", "error")
      local notifs = notify.history()
      assert.equals(1, #notifs)
      assert.equals(1, notifs[1].id)
      assert.equals("ERROR", notifs[1].level)
      assert.are.same({ "test" }, notifs[1].message)
      assert.equals("", notifs[1].title[1])
      assert.equals("string", type(notifs[1].title[2]))
      assert.equals("number", type(notifs[1].time))
    end)

    describe("rendering", function()
      a.it("uses custom render in config", function()
        local called = false
        notify.setup({
          background_colour = "#000000",
          render = function()
            called = true
          end,
        })
        notify.async("test", "error").events.open()
        assert.is.True(called)
      end)

      a.it("uses custom render in call", function()
        local called = false
        notify
          .async("test", "error", {
            render = function()
              called = true
            end,
          }).events
          .open()
        assert.is.True(called)
      end)
    end)

    describe("replacing", function()
      it("inherits options", function()
        local orig = notify.notify("first", "info", { title = "test", icon = "x" })
        local next = notify.notify("second", nil, { replace = orig })

        assert.are.same(
          next,
          vim.tbl_extend("force", orig, { id = next.id, message = next.message })
        )
      end)

      a.it("uses same window", function()
        local orig = async_notify("first", "info", { timeout = false })
        local win = orig.events.open()
        async_notify("second", nil, { replace = orig, timeout = 100 })
        async.util.scheduler()
        local found = false
        local bufs = vim.api.nvim_list_bufs()
        for _, buf in ipairs(bufs) do
          if vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] == "second" then
            assert.Not(found)
            assert.same(vim.fn.bufwinid(buf), win)
            found = true
          end
        end
      end)
    end)
  end)

  a.it("uses the confgured minimum width", function()
    notify.setup({
      background_colour = "#000000",
      minimum_width = 20,
    })
    local win = notify.async("test").events.open()
    assert.equal(vim.api.nvim_win_get_width(win), 20)
  end)

  a.it("uses the configured max width", function()
    notify.setup({
      background_colour = "#000000",
      max_width = function()
        return 3
      end,
    })
    local win = notify.async("test").events.open()
    assert.equal(vim.api.nvim_win_get_width(win), 3)
  end)

  a.it("uses the configured max height", function()
    local instance = notify.instance({
      background_colour = "#000000",
      max_height = function()
        return 3
      end,
    }, false)
    local win = instance.async("test").events.open()
    assert.equal(vim.api.nvim_win_get_height(win), 3)
  end)

  a.it("renders title as longest line", function()
    local instance = notify.instance({
      background_colour = "#000000",
      minimum_width = 10,
    }, false)
    local win = instance.async("test", nil, { title = { string.rep("a", 16), "" } }).events.open()
    assert.equal(21, vim.api.nvim_win_get_width(win))
  end)

  a.it("renders notification above config level", function()
    local win =
      notify.async("test", "info", { message = { string.rep("a", 16), "" } }).events.open()
    assert.Not.Nil(vim.api.nvim_win_get_config(win))
  end)

  a.it("doesn't render notification below config level", function()
    async.run(function()
      local notif = notify.async("test", "debug", { message = { string.rep("a", 16), "" } })
      local win = notif.events.open()
      vim.api.nvim_set_option_value("filetype", "test", { buf = async.api.nvim_win_get_buf(win) })
    end)
    async.util.sleep(100)
    local bufs = vim.api.nvim_list_bufs()
    for _, buf in ipairs(bufs) do
      assert.Not.same(vim.api.nvim_get_option_value("filetype", { buf = buf }), "test")
    end
  end)
  describe("clear_history()", function()
    it("empties the notification history", function()
      notify.notify("first", "info")
      notify.notify("second", "warn")
      assert.is.True(#notify.history() >= 2)
      notify.clear_history()
      assert.are.same({}, notify.history())
    end)
  end)

  describe("dismiss()", function()
    it("does not error with no active notifications", function()
      assert.has_no.errors(function()
        notify.dismiss({ pending = true, silent = true })
      end)
    end)
  end)

  describe("duplicate merging", function()
    it("populates duplicates field when same notification sent twice", function()
      notify.setup({ background_colour = "#000000", merge_duplicates = true })
      notify.notify("duplicate msg", "info", { title = "test" })
      notify.notify("duplicate msg", "info", { title = "test" })
      local history = notify.history()
      local found_dups = false
      for _, notif in ipairs(history) do
        if notif.duplicates and #notif.duplicates > 1 then
          found_dups = true
        end
      end
      assert.is.True(found_dups)
    end)
  end)

  a.it("refreshes timeout on replace", function()
    -- Don't want to spend time animating
    notify.setup({ background_colour = "#000000", stages = "static" })

    local notif = notify.async("test", "error", { timeout = 500 })
    local win = notif.events.open()
    a.util.sleep(300)
    notify.async("test2", "error", { replace = notif })
    a.util.sleep(300)
    a.util.scheduler()
    assert(vim.api.nvim_win_is_valid(win))
  end)
end)
