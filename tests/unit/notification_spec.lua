describe("notification", function()
  local Notification = require("notify.service.notification")
  local config = require("notify.config")

  local test_config

  before_each(function()
    test_config = config.setup({
      background_colour = "#000000",
    })
  end)

  describe("creation", function()
    it("splits string messages on newline", function()
      local notif = Notification(1, "line1\nline2\nline3", "info", {}, test_config)
      assert.are.same({ "line1", "line2", "line3" }, notif.message)
    end)

    it("preserves table messages", function()
      local notif = Notification(1, { "line1", "line2" }, "info", {}, test_config)
      assert.are.same({ "line1", "line2" }, notif.message)
    end)

    it("converts numeric level to string", function()
      local notif = Notification(1, "test", vim.log.levels.ERROR, {}, test_config)
      assert.equals("ERROR", notif.level)
    end)

    it("uppercases string level", function()
      local notif = Notification(1, "test", "warn", {}, test_config)
      assert.equals("WARN", notif.level)
    end)

    it("defaults level to INFO when nil", function()
      local notif = Notification(1, "test", nil, {}, test_config)
      assert.equals("INFO", notif.level)
    end)

    it("sets correct id", function()
      local notif = Notification(42, "test", "info", {}, test_config)
      assert.equals(42, notif.id)
    end)

    it("uses icon from config when not specified in opts", function()
      local notif = Notification(1, "test", "error", {}, test_config)
      assert.equals(test_config.icons().ERROR, notif.icon)
    end)

    it("uses icon from opts when specified", function()
      local notif = Notification(1, "test", "info", { icon = "X" }, test_config)
      assert.equals("X", notif.icon)
    end)

    it("converts string title to table with timestamp", function()
      local notif = Notification(1, "test", "info", { title = "My Title" }, test_config)
      assert.equals("table", type(notif.title))
      assert.equals("My Title", notif.title[1])
      assert.equals("string", type(notif.title[2]))
    end)

    it("preserves string title input on title_input", function()
      local notif = Notification(1, "test", "info", { title = "My Title" }, test_config)
      assert.equals("My Title", notif.title_input)
    end)

    it("preserves single-element table title input", function()
      local notif = Notification(1, "test", "info", { title = { "Solo" } }, test_config)
      assert.equals("table", type(notif.title_input))
      assert.equals(1, #notif.title_input)
      assert.equals("Solo", notif.title_input[1])
    end)

    it("preserves two-element table title input", function()
      local notif = Notification(1, "test", "info", { title = { "L", "R" } }, test_config)
      assert.are.same({ "L", "R" }, notif.title_input)
    end)

    it("title_input is nil when no title given", function()
      local notif = Notification(1, "test", "info", {}, test_config)
      assert.is.Nil(notif.title_input)
    end)

    it("defaults animate to true", function()
      local notif = Notification(1, "test", "info", {}, test_config)
      assert.is.True(notif.animate)
    end)

    it("respects animate = false", function()
      local notif = Notification(1, "test", "info", { animate = false }, test_config)
      assert.is.False(notif.animate)
    end)
  end)

  describe("record()", function()
    it("returns expected structure", function()
      local notif = Notification(1, "test message", "error", { title = "Test" }, test_config)
      local record = notif:record()

      assert.equals(1, record.id)
      assert.are.same({ "test message" }, record.message)
      assert.equals("ERROR", record.level)
      assert.equals("number", type(record.time))
      assert.equals("table", type(record.title))
      assert.equals(test_config.icons().ERROR, record.icon)
    end)

    it("does not include callbacks in record", function()
      local notif = Notification(1, "test", "info", {
        on_open = function() end,
        on_close = function() end,
        keep = function() end,
      }, test_config)
      local record = notif:record()

      assert.is.Nil(record.on_open)
      assert.is.Nil(record.on_close)
      assert.is.Nil(record.keep)
    end)

    it("includes title_input in record", function()
      local notif = Notification(1, "test", "info", { title = { "L", "R" } }, test_config)
      local record = notif:record()
      assert.are.same({ "L", "R" }, record.title_input)
    end)
  end)
end)
