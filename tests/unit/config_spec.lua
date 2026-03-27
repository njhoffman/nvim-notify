describe("config", function()
  local Config = require("notify.config")

  describe("setup()", function()
    it("returns config with all expected accessor functions", function()
      local cfg = Config.setup({})
      local expected_fns = {
        "level",
        "fps",
        "background_colour",
        "time_formats",
        "icons",
        "stages",
        "default_timeout",
        "on_open",
        "on_close",
        "on_replace",
        "render",
        "minimum_width",
        "max_width",
        "max_height",
        "top_down",
        "merge_duplicates",
        "merged",
        "captures",
        "highlights",
        "format",
      }
      for _, fn_name in ipairs(expected_fns) do
        assert.equals("function", type(cfg[fn_name]), "missing config accessor: " .. fn_name)
      end
    end)

    it("uses default values when no config provided", function()
      local cfg = Config.setup({})
      assert.equals(vim.log.levels.INFO, cfg.level())
      assert.equals(30, cfg.fps())
      assert.equals(5000, cfg.default_timeout())
      assert.equals(50, cfg.minimum_width())
      assert.is.True(cfg.top_down())
      assert.is.True(cfg.merge_duplicates())
    end)

    it("overrides defaults with user config", function()
      local cfg = Config.setup({
        timeout = 3000,
        minimum_width = 30,
        fps = 60,
        top_down = false,
      })
      assert.equals(3000, cfg.default_timeout())
      assert.equals(30, cfg.minimum_width())
      assert.equals(60, cfg.fps())
      assert.is.False(cfg.top_down())
    end)
  end)

  describe("level()", function()
    it("resolves string level to numeric", function()
      local cfg = Config.setup({ level = "warn" })
      assert.equals(vim.log.levels.WARN, cfg.level())
    end)

    it("passes through numeric level", function()
      local cfg = Config.setup({ level = vim.log.levels.ERROR })
      assert.equals(vim.log.levels.ERROR, cfg.level())
    end)
  end)

  describe("max_width()", function()
    it("returns nil by default", function()
      local cfg = Config.setup({})
      assert.is.Nil(cfg.max_width())
    end)

    it("returns numeric value directly", function()
      local cfg = Config.setup({ max_width = 80 })
      assert.equals(80, cfg.max_width())
    end)

    it("calls function when max_width is callable", function()
      local cfg = Config.setup({
        max_width = function()
          return 42
        end,
      })
      assert.equals(42, cfg.max_width())
    end)
  end)

  describe("max_height()", function()
    it("returns nil by default", function()
      local cfg = Config.setup({})
      assert.is.Nil(cfg.max_height())
    end)

    it("calls function when max_height is callable", function()
      local cfg = Config.setup({
        max_height = function()
          return 10
        end,
      })
      assert.equals(10, cfg.max_height())
    end)
  end)

  describe("_format_default()", function()
    it("does not error", function()
      assert.has_no.errors(function()
        Config._format_default()
      end)
    end)

    it("returns a table of lines", function()
      local lines = Config._format_default()
      assert.equals("table", type(lines))
      assert.is.True(#lines > 0)
    end)
  end)

  describe("merged()", function()
    it("returns full merged config table", function()
      local cfg = Config.setup({ timeout = 9999 })
      local merged = cfg.merged()
      assert.equals("table", type(merged))
      assert.equals(9999, merged.timeout)
      assert.equals(50, merged.minimum_width)
    end)
  end)
end)
