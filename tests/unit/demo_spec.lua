describe("notify.demo", function()
  local demo = require("notify.demo")

  describe("get_config()", function()
    it("returns defaults when called with no arguments", function()
      local cfg = demo.get_config()
      assert.equals(200, cfg.opts.delay)
      assert.equals(3000, cfg.opts.notify_timeout)
      assert.equals(4000, cfg.opts.group_timeout)
      assert.equals("fade_in_slide_out", cfg.opts.stages)
      assert.are.same({ "trace", "debug", "info", "warn", "error" }, cfg.opts.levels)
      assert.equals("table", type(cfg.variants))
    end)

    it("overrides opts from user input", function()
      local cfg = demo.get_config(nil, { delay = 50, notify_timeout = 1000 })
      assert.equals(50, cfg.opts.delay)
      assert.equals(1000, cfg.opts.notify_timeout)
      assert.equals(4000, cfg.opts.group_timeout)
    end)

    it("replaces variants wholesale when provided", function()
      local my_variants = { custom = { body = "x" } }
      local cfg = demo.get_config(my_variants)
      assert.are.same(my_variants, cfg.variants)
    end)

    it("does not mutate the default opts table across calls", function()
      local first = demo.get_config(nil, { delay = 10 })
      local second = demo.get_config()
      assert.equals(10, first.opts.delay)
      assert.equals(200, second.opts.delay)
    end)
  end)

  describe("template_lines()", function()
    local lines

    before_each(function()
      lines = demo.template_lines()
    end)

    it("returns a non-empty list of lines", function()
      assert.is.truthy(#lines > 0)
    end)

    it("produces source that evaluates to a table with opts and variants", function()
      local chunk, err = loadstring(table.concat(lines, "\n"))
      assert.is.Nil(err)
      assert.is.truthy(chunk)
      local ok, result = pcall(chunk)
      assert.is.True(ok)
      assert.equals("table", type(result))
      assert.equals("table", type(result.opts))
      assert.equals("table", type(result.variants))
      assert.equals(200, result.opts.delay)
    end)
  end)

  describe("open_scratch()", function()
    local created_bufs = {}

    after_each(function()
      for _, bufnr in ipairs(created_bufs) do
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_delete(bufnr, { force = true })
        end
      end
      created_bufs = {}
    end)

    it("creates an unlisted scratch buffer with template content", function()
      local bufnr = demo.open_scratch()
      table.insert(created_bufs, bufnr)
      assert.is.True(vim.api.nvim_buf_is_valid(bufnr))
      assert.equals("nofile", vim.api.nvim_get_option_value("buftype", { buf = bufnr }))
      assert.equals("wipe", vim.api.nvim_get_option_value("bufhidden", { buf = bufnr }))
      assert.equals("lua", vim.api.nvim_get_option_value("filetype", { buf = bufnr }))
      local marker = vim.api.nvim_buf_get_var(bufnr, "notify_demo_scratch")
      assert.is.True(marker)

      local first_line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
      assert.is.truthy(first_line:match("nvim%-notify demo options"))
    end)

    it("reuses the existing scratch buffer on a second invocation", function()
      local first = demo.open_scratch()
      table.insert(created_bufs, first)
      local second = demo.open_scratch()
      assert.equals(first, second)
    end)

    it("binds <CR> and q keymaps in the scratch buffer", function()
      local bufnr = demo.open_scratch()
      table.insert(created_bufs, bufnr)
      local maps = vim.api.nvim_buf_get_keymap(bufnr, "n")
      local has_cr, has_q = false, false
      for _, map in ipairs(maps) do
        if map.lhs == "<CR>" then
          has_cr = true
        end
        if map.lhs == "q" then
          has_q = true
        end
      end
      assert.is.True(has_cr)
      assert.is.True(has_q)
    end)
  end)

  describe("parse_buffer()", function()
    local bufnrs = {}

    local function scratch_with(lines)
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      table.insert(bufnrs, bufnr)
      return bufnr
    end

    after_each(function()
      for _, bufnr in ipairs(bufnrs) do
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_delete(bufnr, { force = true })
        end
      end
      bufnrs = {}
    end)

    it("returns the evaluated table for valid Lua source", function()
      local bufnr = scratch_with({ "return { opts = { delay = 7 }, variants = {} }" })
      local ok, result = demo.parse_buffer(bufnr)
      assert.is.True(ok)
      assert.equals(7, result.opts.delay)
      assert.are.same({}, result.variants)
    end)

    it("returns false with a message for syntactically invalid source", function()
      local bufnr = scratch_with({ "return { opts = " })
      local ok, err = demo.parse_buffer(bufnr)
      assert.is.False(ok)
      assert.equals("string", type(err))
    end)

    it("returns false when the chunk returns a non-table", function()
      local bufnr = scratch_with({ "return 42" })
      local ok, err = demo.parse_buffer(bufnr)
      assert.is.False(ok)
      assert.is.truthy(err:match("must return a table"))
    end)

    it("returns false when the chunk raises at runtime", function()
      local bufnr = scratch_with({ "error('boom')" })
      local ok, err = demo.parse_buffer(bufnr)
      assert.is.False(ok)
      assert.is.truthy(err:match("boom"))
    end)
  end)

  describe("run_from_buffer()", function()
    local saved_demo
    local created_bufs = {}

    before_each(function()
      saved_demo = package.loaded["notify.demo.demo"]
      package.loaded["notify.demo.demo"] = {
        run = function(cfg)
          package.loaded["notify.demo.demo"].last_cfg = cfg
          return true
        end,
        stop = function() end,
      }
    end)

    after_each(function()
      package.loaded["notify.demo.demo"] = saved_demo
      for _, bufnr in ipairs(created_bufs) do
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_delete(bufnr, { force = true })
        end
      end
      created_bufs = {}
    end)

    it("runs the demo with the merged config and deletes the buffer", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      table.insert(created_bufs, bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "return { opts = { delay = 11 }, variants = { only = { body = 'hi' } } }",
      })
      local ok = demo.run_from_buffer(bufnr)
      assert.is.True(ok)
      assert.is.False(vim.api.nvim_buf_is_valid(bufnr))
      local cfg = package.loaded["notify.demo.demo"].last_cfg
      assert.equals(11, cfg.opts.delay)
      assert.equals(3000, cfg.opts.notify_timeout)
      assert.are.same({ only = { body = "hi" } }, cfg.variants)
    end)

    it("returns false and does not run when buffer is invalid Lua", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      table.insert(created_bufs, bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "not valid lua =" })
      local ok = demo.run_from_buffer(bufnr)
      assert.is.False(ok)
      assert.is.Nil(package.loaded["notify.demo.demo"].last_cfg)
    end)
  end)

  describe("stop()", function()
    it("flips the demo module's active flag to false", function()
      local demo_mod = require("notify.demo.demo")
      demo_mod.active = true
      demo_mod._token = {}
      demo.stop()
      assert.is.False(demo_mod.active)
    end)
  end)

  describe("command swapping", function()
    local RUN_CMD = "NotificationsDemo"
    local STOP_CMD = "NotificationsDemoStop"
    local saved_demo
    local created_bufs = {}

    local function command_exists(name)
      return vim.fn.exists(":" .. name) == 2
    end

    before_each(function()
      pcall(vim.api.nvim_del_user_command, RUN_CMD)
      pcall(vim.api.nvim_del_user_command, STOP_CMD)
      saved_demo = package.loaded["notify.demo.demo"]
      package.loaded["notify.demo.demo"] = {
        active = false,
        _token = nil,
        run = function(_, _)
          package.loaded["notify.demo.demo"].active = true
          package.loaded["notify.demo.demo"]._token = {}
          return true
        end,
        stop = function()
          local mod = package.loaded["notify.demo.demo"]
          if not mod.active then
            return false
          end
          mod.active = false
          mod._token = nil
          return true
        end,
      }
    end)

    after_each(function()
      package.loaded["notify.demo.demo"] = saved_demo
      pcall(vim.api.nvim_del_user_command, RUN_CMD)
      pcall(vim.api.nvim_del_user_command, STOP_CMD)
      for _, bufnr in ipairs(created_bufs) do
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_delete(bufnr, { force = true })
        end
      end
      created_bufs = {}
    end)

    it("register_commands() creates NotificationsDemo and not the stop cmd", function()
      demo.register_commands()
      assert.is.True(command_exists(RUN_CMD))
      assert.is.False(command_exists(STOP_CMD))
    end)

    it("running from a buffer swaps NotificationsDemo -> NotificationsDemoStop", function()
      demo.register_commands()
      local bufnr = vim.api.nvim_create_buf(false, true)
      table.insert(created_bufs, bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "return { opts = {}, variants = {} }",
      })
      demo.run_from_buffer(bufnr)
      assert.is.False(command_exists(RUN_CMD))
      assert.is.True(command_exists(STOP_CMD))
    end)

    it("stop() swaps NotificationsDemoStop -> NotificationsDemo", function()
      demo.register_commands()
      local bufnr = vim.api.nvim_create_buf(false, true)
      table.insert(created_bufs, bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "return { opts = {}, variants = {} }",
      })
      demo.run_from_buffer(bufnr)
      assert.is.True(command_exists(STOP_CMD))

      demo.stop()
      assert.is.True(command_exists(RUN_CMD))
      assert.is.False(command_exists(STOP_CMD))
    end)

    it("stop() is a no-op when no demo is running", function()
      demo.register_commands()
      assert.is.True(command_exists(RUN_CMD))
      demo.stop()
      assert.is.True(command_exists(RUN_CMD))
      assert.is.False(command_exists(STOP_CMD))
    end)

    it("natural completion restores NotificationsDemo via on_complete callback", function()
      demo.register_commands()
      package.loaded["notify.demo.demo"].run = function(_, on_complete)
        package.loaded["notify.demo.demo"].active = true
        package.loaded["notify.demo.demo"]._token = {}
        if on_complete then
          on_complete()
        end
        return true
      end

      local bufnr = vim.api.nvim_create_buf(false, true)
      table.insert(created_bufs, bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "return { opts = {}, variants = {} }",
      })
      demo.run_from_buffer(bufnr)

      assert.is.True(command_exists(RUN_CMD))
      assert.is.False(command_exists(STOP_CMD))
    end)

    it("restores NotificationsDemo if run() reports it did not start", function()
      demo.register_commands()
      package.loaded["notify.demo.demo"].run = function()
        return false
      end
      local bufnr = vim.api.nvim_create_buf(false, true)
      table.insert(created_bufs, bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "return { opts = {}, variants = {} }",
      })
      local ok = demo.run_from_buffer(bufnr)
      assert.is.False(ok)
      assert.is.True(command_exists(RUN_CMD))
      assert.is.False(command_exists(STOP_CMD))
    end)
  end)
end)
