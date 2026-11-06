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
