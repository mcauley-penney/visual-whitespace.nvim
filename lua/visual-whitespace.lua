local api = vim.api
local fn = vim.fn

local M = {}
local LAST_POS = nil
local NS_ID = api.nvim_create_namespace('VisualWhitespace')

local cfg = {
  highlight = { link = 'Visual' },
  space_char = '·',
  tab_char = '→',
  nl_char = '↲'
}

local function del_marked_ws(s_pos, e_pos)
  local adjusted_s_pos = { s_pos[1] - 1, s_pos[2] - 1 }
  local adjusted_e_pos = { e_pos[1] - 1, e_pos[2] - 1 }

  local marks = api.nvim_buf_get_extmarks(0, NS_ID, adjusted_s_pos, adjusted_e_pos, {})

  for _, mark_tbl in ipairs(marks) do
    api.nvim_buf_del_extmark(0, NS_ID, mark_tbl[1])
  end
end

local function get_visual_selection_data(srow, scol, erow, ecol)
  if srow < erow or (srow == erow and scol <= ecol) then
    return {
      false,
      srow,
      scol,
      erow,
      ecol,
    }
  else
    return {
      true,
      erow,
      ecol,
      srow,
      scol
    }
  end
end

local function set_mark(row, col, text)
  api.nvim_buf_set_extmark(0, NS_ID, row - 1, col - 1, {
    virt_text = { { text, 'VisualNonText' } },
    virt_text_pos = 'overlay',
  })
end

M.mark_ws = function()
  local ff = vim.bo.fileformat
  local nl_str = ff == 'unix' and '\n' or ff == 'mac' and '\r' or '\r\n'
  local cur_mode = fn.mode()

  local _, reverse, srow, scol, erow, ecol
  if cur_mode == 'v' then
    _, srow, scol = table.unpack(fn.getpos('v'))
    _, erow, ecol = table.unpack(fn.getpos('.'))
  else
    return
  end

  reverse, srow, scol, erow, ecol = table.unpack(get_visual_selection_data(srow, scol, erow, ecol))

  local e_pos = nil
  if not reverse then
    e_pos = { erow, ecol }
  else
    e_pos = { srow, scol }
  end

  if LAST_POS ~= nil then
    del_marked_ws(LAST_POS, e_pos)
  end

  LAST_POS = e_pos

  for cur_row = srow, erow do
    -- gets the physical line, not the display line
    local line_text = fn.getline(cur_row) .. nl_str

    -- adjust start_col and end_col for partial line selections
    local select_scol = (cur_row == srow) and scol or 1
    local select_ecol = (cur_row == erow) and ecol or #line_text

    for cur_col = select_scol, select_ecol do
      local cur_char = line_text:sub(cur_col, cur_col)

      if cur_char == ' ' then
        set_mark(cur_row, cur_col, cfg['space_char'])
      elseif cur_char == '\t' then
        set_mark(cur_row, cur_col, cfg['tab_char'])
      elseif cur_char == nl_str then
        set_mark(cur_row, cur_col, cfg['nl_char'])
      end
    end
  end
end

M.clear_marked_ws = function()
  api.nvim_buf_clear_namespace(0, NS_ID, 0, -1)
end

M.setup = function(user_cfg)
  cfg = vim.tbl_extend('force', cfg, user_cfg or {})

  api.nvim_set_hl(0, 'VisualNonText', cfg['highlight'])
end

return M
