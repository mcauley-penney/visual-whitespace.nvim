local match_vis = require("visual-whitespace")
local aucmd = vim.api.nvim_create_autocmd
local augrp = vim.api.nvim_create_augroup("VisualWhitespace", { clear = true })

aucmd("ModeChanged", {
  group = augrp,
  pattern = "*:[vV]",
  callback = match_vis.highlight_ws
})

aucmd("CursorMoved", {
  group = augrp,
  callback = function()
    return vim.schedule(match_vis.highlight_ws)
  end
})

aucmd("ModeChanged", {
  group = augrp,
  pattern = "[vV]:*",
  callback = match_vis.clear_ws_hl
})
