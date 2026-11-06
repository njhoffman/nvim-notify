local spring = require("notify.animate.spring")
local stage_util = require("notify.stages.util")

describe("spring", function()
  for _, damping in ipairs({ 0.9, 1, 2 }) do
    it("settles on the goal with damping " .. damping, function()
      local state = { position = 0 }
      for _ = 1, 300 do
        spring(1 / 30, 10, state, 1, damping)
      end
      assert.is_true(math.abs(state.position - 10) < 0.01)
      assert.is_true(math.abs(state.velocity) < 0.01)
    end)
  end

  it("moves an overdamped spring gradually towards the goal", function()
    local state = { position = 0 }
    spring(1 / 30, 10, state, 1, 2)
    assert.is_true(state.position > 0 and state.position < 1)
    assert.is_true(state.velocity > 0)
  end)
end)

describe("available_slot", function()
  local wins = {}

  local function open_at(row, height)
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, false, {
      relative = "editor",
      row = row,
      col = 0,
      width = 5,
      height = height,
      border = "rounded",
    })
    table.insert(wins, win)
  end

  local function close_all()
    for _, win in ipairs(wins) do
      pcall(vim.api.nvim_win_close, win, true)
    end
    wins = {}
  end

  --- Stack windows until the screen is reported full, returning each slot given.
  local function fill(direction, height)
    local slots = {}
    for _ = 1, 100 do
      -- Height plus the two border rows.
      local slot = stage_util.available_slot(wins, height + 2, direction)
      if not slot then
        return slots
      end
      table.insert(slots, slot)
      open_at(slot, height)
    end
    error("available_slot never reported a full screen")
  end

  after_each(close_all)

  -- Several heights, because a window only overflows when the stack does not fit the screen exactly.
  for height = 1, 8 do
    it("keeps bottom-up windows of height " .. height .. " on the screen", function()
      local top = select(2, stage_util.get_slot_range(stage_util.DIRECTION.BOTTOM_UP))
      for _, slot in ipairs(fill(stage_util.DIRECTION.BOTTOM_UP, height)) do
        assert.is_true(slot >= top, "slot " .. slot .. " is above the top row " .. top)
      end
    end)

    it("keeps top-down windows of height " .. height .. " on the screen", function()
      local bottom = select(2, stage_util.get_slot_range(stage_util.DIRECTION.TOP_DOWN))
      for _, slot in ipairs(fill(stage_util.DIRECTION.TOP_DOWN, height)) do
        assert.is_true(slot + height + 1 <= bottom)
      end
    end)
  end
end)

describe("border padding", function()
  local wins = {}
  local DASH = "─"
  local BAR = "│"

  local function open(border)
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, false, {
      relative = "editor",
      row = 0,
      col = 0,
      width = 10,
      height = 3,
      border = border,
    })
    table.insert(wins, win)
    return win
  end

  after_each(function()
    for _, win in ipairs(wins) do
      pcall(vim.api.nvim_win_close, win, true)
    end
    wins = {}
  end)

  local vertical = {
    { "none", "none", 3 },
    { "rounded", "rounded", 5 },
    { "top and bottom", { "", DASH, "", "", "", DASH, "", "" }, 5 },
    { "top only", { "", DASH, "", "", "", "", "", "" }, 4 },
    { "bottom only", { "", "", "", "", "", DASH, "", "" }, 4 },
    { "left and right only", { "", "", "", BAR, "", "", "", BAR }, 3 },
    { "highlighted top only", { "", { DASH, "Title" }, "", "", "", "", "", "" }, 4 },
    { "shadow", "shadow", 4 },
    { "highlighted empty top", { "", { "", "Title" }, "", "", "", DASH, "", "" }, 4 },
  }

  for _, case in ipairs(vertical) do
    it("stacks below a window with border " .. case[1], function()
      local win = open(case[2])
      local slot = stage_util.available_slot({ win }, 2, stage_util.DIRECTION.TOP_DOWN)
      assert.equals(case[3], slot)
    end)
  end

  it("counts the left and right sides when stacking sideways", function()
    local win = open({ "", "", "", BAR, "", "", "", "" })
    local slot = stage_util.available_slot({ win }, 2, stage_util.DIRECTION.LEFT_RIGHT)
    -- Width 10 plus the one right-hand side, from column 0.
    assert.equals(11, slot)
  end)
end)

describe("treesitter highlights", function()
  local NotifyBufHighlights = require("notify.service.buffer.highlights")

  local function config()
    return {
      background_colour = function()
        return 0
      end,
    }
  end

  it("fades highlighted text in a filetype buffer", function()
    vim.api.nvim_set_hl(0, "@comment.lua", { fg = "#ffffff" })
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local x = 1 -- note" })
    vim.api.nvim_set_option_value("filetype", "lua", { buf = buf })
    -- tests/init.vim leaves parsers off the runtimepath, so add the ones bundled with nvim.
    local prefix = vim.fn.fnamemodify(vim.v.progpath, ":h:h")
    vim.opt.runtimepath:append(prefix .. "/lib/nvim")
    local parser = vim.treesitter.get_parser(buf, "lua", { error = false })
    assert.is_not_nil(parser, "no lua parser under " .. prefix .. "/lib/nvim")
    parser:parse()
    local ts_highlighter = vim.treesitter.highlighter.new(parser)

    local hl = NotifyBufHighlights({ level = "INFO" }, buf, config())
    hl:set_opacity(50)

    local group = "@comment.lua" .. buf
    assert.is_truthy(hl.groups[group])
    assert.equals(0x808080, vim.api.nvim_get_hl(hl.namespace, { name = group }).fg)

    local ns = vim.api.nvim_create_namespace("notify-treesitter-override")
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    local found = false
    for _, mark in ipairs(marks) do
      if mark[4].hl_group == group then
        found = true
        assert.equals(12, mark[3])
      end
    end
    assert.is.True(found)

    hl:clear()
    ts_highlighter:destroy()
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("does nothing when treesitter is not highlighting the buffer", function()
    local prefix = vim.fn.fnamemodify(vim.v.progpath, ":h:h")
    vim.opt.runtimepath:append(prefix .. "/lib/nvim")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local x = 1 -- note" })
    vim.api.nvim_set_option_value("filetype", "lua", { buf = buf })
    local parser = vim.treesitter.get_parser(buf, "lua", { error = false })
    assert.is_not_nil(parser)
    parser:parse()

    local hl = NotifyBufHighlights({ level = "INFO" }, buf, config())
    hl:set_opacity(50)

    assert.is_nil(hl._treesitter_redefined)
    local ns = vim.api.nvim_create_namespace("notify-treesitter-override")
    assert.same({}, vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}))
    hl:clear()
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
