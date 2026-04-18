describe("util.log", function()
  local LEVELS = { "trace", "debug", "info", "warn", "error", "fatal" }

  local function fresh_log()
    package.loaded["notify.util.log"] = nil
    return require("notify.util.log")
  end

  local function make_stub_logger()
    local calls = {}
    local logger = { __calls = calls }
    for _, level in ipairs(LEVELS) do
      logger[level] = function(...)
        table.insert(calls, { level = level, args = { ... } })
      end
    end
    return logger
  end

  local original_plenary_log
  local plenary_log_stub

  before_each(function()
    original_plenary_log = package.loaded["plenary.log"]
    plenary_log_stub = {
      received = nil,
      new = function(opts)
        plenary_log_stub.received = opts
        return make_stub_logger()
      end,
    }
    package.loaded["plenary.log"] = plenary_log_stub
  end)

  after_each(function()
    package.loaded["plenary.log"] = original_plenary_log
    package.loaded["notify.util.log"] = nil
  end)

  describe("setup()", function()
    it("uses plenary defaults when value is nil", function()
      local log = fresh_log()
      log.setup(nil)
      assert.are.same({
        plugin = "nvim-notify",
        use_console = false,
        use_quickfix = false,
        use_file = true,
        outfile = nil,
        level = "info",
      }, plenary_log_stub.received)
    end)

    it("merges a plain table over plenary defaults", function()
      local log = fresh_log()
      log.setup({ level = "trace", outfile = "/tmp/custom.log" })
      assert.equals("nvim-notify", plenary_log_stub.received.plugin)
      assert.equals("trace", plenary_log_stub.received.level)
      assert.equals("/tmp/custom.log", plenary_log_stub.received.outfile)
      assert.is.False(plenary_log_stub.received.use_console)
    end)

    it("uses a prebuilt logger table with level methods as-is", function()
      local log = fresh_log()
      local prebuilt = make_stub_logger()
      log.setup(prebuilt)
      log.info("hello", "world")
      assert.equals(1, #prebuilt.__calls)
      assert.equals("info", prebuilt.__calls[1].level)
      assert.are.same({ "hello", "world" }, prebuilt.__calls[1].args)
      assert.is.Nil(plenary_log_stub.received)
    end)

    it("uses logger returned by a factory function", function()
      local log = fresh_log()
      local prebuilt = make_stub_logger()
      log.setup(function()
        return prebuilt
      end)
      log.warn("msg")
      assert.equals(1, #prebuilt.__calls)
      assert.equals("warn", prebuilt.__calls[1].level)
    end)

    it("wraps a function returning a (level, ...) sink", function()
      local log = fresh_log()
      local sink_calls = {}
      log.setup(function()
        return function(level, ...)
          table.insert(sink_calls, { level = level, args = { ... } })
        end
      end)
      log.error("boom", 42)
      assert.equals(1, #sink_calls)
      assert.equals("error", sink_calls[1].level)
      assert.are.same({ "boom", 42 }, sink_calls[1].args)
    end)

    it("falls back to default plenary when factory returns an invalid value", function()
      local log = fresh_log()
      log.setup(function()
        return 42
      end)
      assert.equals("nvim-notify", plenary_log_stub.received.plugin)
      assert.equals("info", plenary_log_stub.received.level)
    end)

    it("falls back to default plenary for non-table non-function values", function()
      local log = fresh_log()
      log.setup(true)
      assert.equals("nvim-notify", plenary_log_stub.received.plugin)
    end)

    it("falls back to default plenary when factory raises an error", function()
      local log = fresh_log()
      log.setup(function()
        error("boom")
      end)
      assert.equals("nvim-notify", plenary_log_stub.received.plugin)
    end)
  end)

  describe("lazy initialization", function()
    it("builds a default logger on first level call when setup is skipped", function()
      local log = fresh_log()
      log.debug("first call")
      assert.equals("nvim-notify", plenary_log_stub.received.plugin)
    end)
  end)

  describe("level methods", function()
    it("exposes all six level functions on the module", function()
      local log = fresh_log()
      for _, level in ipairs(LEVELS) do
        assert.equals("function", type(log[level]))
      end
    end)

    it("forwards calls to the active logger after re-setup", function()
      local log = fresh_log()
      local first = make_stub_logger()
      log.setup(first)
      log.info("a")
      local second = make_stub_logger()
      log.setup(second)
      log.info("b")
      assert.equals(1, #first.__calls)
      assert.equals(1, #second.__calls)
      assert.are.same({ "b" }, second.__calls[1].args)
    end)
  end)
end)
