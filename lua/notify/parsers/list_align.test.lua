local list_align = require('notify.parsers.list_align')
local col_2_1 = {
  { [1] = 'oldfiles', [2] = '152' },
  { [1] = 'changes', [2] = '102' },
  { [1] = 'history', [2] = '7,555' },
  { [1] = 'timers', [2] = '18' },
}

local lines, hls = list_align(col_2_1)
require('notify')(lines, 2, {
  timeout = 6000,
  -- title = { title, '' },
  render = 'simple-notitle',
  highlights = { body = hls },
  -- hide_from_history = true,
})
