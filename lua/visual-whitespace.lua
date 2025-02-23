local api = vim.api
local fn = vim.fn
local aucmd = api.nvim_create_autocmd
local hl_augrp = api.nvim_create_augroup("VisualWhitespaceHL", { clear = true })
local core_augrp = api.nvim_create_augroup("VisualWhitespace", { clear = true })

local M = {}
local NS_ID = api.nvim_create_namespace('VisualWhitespace')
local CFG = {
  highlight = { link = "Visual", default = true },
  space_char = '·',
  tab_char = '→',
  nl_char = '↲',
  cr_char = '←',
  nbsp_char = '⎵',
  enabled = true,
  excluded = {
    filetypes = {},
    buftypes = {}
  }
}
local CHAR_LOOKUP


local function get_charwise_pos(s_pos, e_pos)
  local srow, scol = s_pos[2], s_pos[3]
  local erow, ecol = e_pos[2], e_pos[3]
  s_pos = { srow, scol }
  e_pos = { erow, ecol }

  -- reverse condition, i.e. visual mode moving up the buffer
  if srow > erow or (srow == erow and scol >= ecol) then
    s_pos, e_pos = e_pos, s_pos
  end

  return s_pos, e_pos
end

local function get_linewise_pos(s_pos, e_pos)
  local srow, scol = s_pos[2], 1
  local erow, ecol = e_pos[2], vim.v.maxcol

  -- reverse condition; start pos = srow, maxcol; end pos = erow, 1
  if srow > erow then
    srow, erow = erow, srow
  end

  return { srow, scol }, { erow, ecol }
end

local function get_marks(s_pos, e_pos, mode)
  local ff = vim.bo.fileformat
  local nl_str = ff == 'unix' and '\n' or ff == 'mac' and '\r' or '\r\n'

  local srow, scol = s_pos[1], s_pos[2]
  local erow, ecol = e_pos[1], e_pos[2]

  local text = api.nvim_buf_get_lines(0, srow - 1, erow, true)

  local line_text, line_len, adjusted_scol, adjusted_ecol, match_char
  local ws_marks = {}
  for cur_row = srow, erow do
    -- gets the physical line, not the display line
    line_text = table.concat { text[cur_row - srow + 1], nl_str }
    line_len = #line_text

    -- adjust start_col and end_col for partial line selections
    if mode == 'v' then
      adjusted_scol = (cur_row == srow) and scol or 1
      adjusted_ecol = (cur_row == erow) and ecol or line_len

      --[[
        There are four ranges to manage:
          1. start to end
          2. start to middle
          3. middle to middle
          4. middle to end

        In cases 2 and 3, we can get a substring to the
        end column which the start column is always inside of, e.g.
        1 to ecol, so that we can continue using string.find().
      ]]
      if (adjusted_ecol ~= line_len) then
        line_text = line_text:sub(1, adjusted_ecol)
      end
    else
      adjusted_scol = scol
    end

    -- process columns of current line
    repeat
      adjusted_scol, _, match_char = string.find(line_text, "([ \160\t\r\n])", adjusted_scol)

      if adjusted_scol then
        if ff == 'dos' and line_len == adjusted_scol then
          table.insert(ws_marks, { cur_row, 0, CHAR_LOOKUP[match_char], "eol" })
        else
		  local offset = match_char == "\160" and 1 or 0 
          table.insert(ws_marks, { cur_row, adjusted_scol - offset, CHAR_LOOKUP[match_char], "overlay" })
        end

        adjusted_scol = adjusted_scol + 1
      end
    until not adjusted_scol
  end

  return ws_marks
end

local function apply_marks(mark_table)
  for _, mark_data in ipairs(mark_table) do
    api.nvim_buf_set_extmark(0, NS_ID, mark_data[1] - 1, mark_data[2] - 1, {
      virt_text = { { mark_data[3], 'VisualNonText' } },
      virt_text_pos = mark_data[4],
    })
  end
end

local clear_ws_hl = function()
  api.nvim_buf_clear_namespace(0, NS_ID, 0, -1)
end

local highlight_ws = function()
  local cur_mode = fn.mode()

  if cur_mode ~= 'v' and cur_mode ~= 'V' then
    return
  end

  local s_pos = fn.getpos('v')
  local e_pos = fn.getpos('.')

  if cur_mode == 'v' then
    s_pos, e_pos = get_charwise_pos(s_pos, e_pos)
  else
    s_pos, e_pos = get_linewise_pos(s_pos, e_pos)
  end

  clear_ws_hl()

  local marks = get_marks(s_pos, e_pos, cur_mode)

  apply_marks(marks)
end

local function is_enabled_ft_bt()
  local contains = vim.fn.has('nvim-0.10') == 1 and vim.list_contains or vim.tbl_contains

  local bufnr = vim.api.nvim_get_current_buf()
  local ft = vim.api.nvim_buf_get_option(bufnr, "filetype")
  local bt = vim.api.nvim_buf_get_option(bufnr, "buftype")

  local ft_list = CFG.excluded.filetypes or {}
  local bt_list = CFG.excluded.buftypes or {}

  return not contains(ft_list, ft) and not contains(bt_list, bt)
end

local function init_aucmds()
  if CFG.enabled then
    aucmd("ModeChanged", {
      group = hl_augrp,
      pattern = "*:[vV]",
      callback = function()
        return highlight_ws()
      end
    })

    aucmd("CursorMoved", {
      group = hl_augrp,
      callback = function()
        return vim.schedule(highlight_ws)
      end
    })

    aucmd("ModeChanged", {
      group = hl_augrp,
      pattern = "[vV]:[^vV]",
      callback = function()
        return clear_ws_hl()
      end
    })
  else
    vim.api.nvim_clear_autocmds({ group = hl_augrp })
  end
end

M.toggle = function()
  CFG.enabled = not CFG.enabled

  init_aucmds()

  if not CFG.enabled then
    vim.notify("visual-whitespace disabled", vim.log.levels.WARN, { title = "visual-whitespace" })
  else
    vim.notify("visual-whitespace enabled", vim.log.levels.INFO, { title = "visual-whitespace" })
  end
end

M.setup = function(user_cfg)
  CFG = vim.tbl_extend('force', CFG, user_cfg or {})
  CHAR_LOOKUP = {
    [' '] = CFG['space_char'],
    ['\160'] = CFG['nbsp_char'],
    ['\t'] = CFG['tab_char'],
    ['\n'] = CFG['nl_char'],
    ['\r'] = CFG['cr_char']
  }
  api.nvim_set_hl(0, 'VisualNonText', CFG['highlight'])

  aucmd({ "BufEnter", "WinEnter" }, {
    group = core_augrp,
    callback = vim.schedule_wrap(function()
      local prev_enabled = CFG.enabled
      CFG.enabled = is_enabled_ft_bt()

      if prev_enabled ~= CFG.enabled then
        init_aucmds()
      end
    end)
  })

  aucmd({ "ColorScheme" }, {
    group = core_augrp,
    callback = function()
      api.nvim_set_hl(0, 'VisualNonText', CFG['highlight'])
    end
  })

  init_aucmds()
end


return M
