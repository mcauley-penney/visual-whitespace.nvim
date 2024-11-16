local visual_ws = require('visual-whitespace')

if not visual_ws.setup_called then
  visual_ws.setup({})
end

visual_ws.setup_called = true
