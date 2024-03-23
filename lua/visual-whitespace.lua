local api = vim.api
local fn = vim.fn

local M = {}
local NS_ID = api.nvim_create_namespace('VisualWhitespace')
local CFG = {
  highlight = { link = "Visual" },
  space_char = '·',
  tab_char = '→',
  nl_char = '↲'
}


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

  local line_text, select_scol, select_ecol, cur_char
  local ws_marks = {}
  for cur_row = srow, erow do
    -- gets the physical line, not the display line
    line_text = table.concat { text[cur_row - srow + 1], nl_str }

    -- adjust start_col and end_col for partial line selections
    if mode == 'v' then
      select_scol = (cur_row == srow) and scol or 1
      select_ecol = (cur_row == erow) and ecol or #line_text
    else
      select_scol = scol
      select_ecol = #line_text
    end

    for cur_col = select_scol, select_ecol do
      cur_char = line_text:sub(cur_col, cur_col)

      if cur_char == ' ' then
        table.insert(ws_marks, { cur_row, cur_col, CFG['space_char'] })
      elseif cur_char == '\t' then
        table.insert(ws_marks, { cur_row, cur_col, CFG['tab_char'] })
      elseif cur_char == nl_str then
        table.insert(ws_marks, { cur_row, cur_col, CFG['nl_char'] })
      end
    end
  end

  return ws_marks
end

local function apply_marks(mark_table)
  for _, mark_data in ipairs(mark_table) do
    api.nvim_buf_set_extmark(0, NS_ID, mark_data[1] - 1, mark_data[2] - 1, {
      virt_text = { { mark_data[3], 'VisualNonText' } },
      virt_text_pos = 'overlay',
    })
  end
end

M.clear_ws_hl = function()
  api.nvim_buf_clear_namespace(0, NS_ID, 0, -1)
end

M.highlight_ws = function()
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

  M.clear_ws_hl()

  local marks = get_marks(s_pos, e_pos, cur_mode)

  apply_marks(marks)
end

M.setup = function(user_cfg)
  CFG = vim.tbl_extend('force', CFG, user_cfg or {})

  api.nvim_set_hl(0, 'VisualNonText', CFG['highlight'])
end


return M
