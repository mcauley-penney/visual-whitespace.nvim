local api = vim.api
local fn = vim.fn

local M = {}
local LAST_POS = nil
local NS_ID = api.nvim_create_namespace('VisualWhitespace')

local cfg = {
  highlight = { fg = "#ed333b" },
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

local function set_mark(row, col, text)
  api.nvim_buf_set_extmark(0, NS_ID, row - 1, col - 1, {
    virt_text = { { text, 'VisualNonText' } },
    virt_text_pos = 'overlay',
  })
end

M.mark_ws = function()
  local cur_mode = fn.mode()

  if cur_mode ~= 'v' then
    return
  end

  local ff = vim.bo.fileformat
  local nl_str = ff == 'unix' and '\n' or ff == 'mac' and '\r' or '\r\n'

  local s_pos = fn.getpos('v')
  local e_pos = fn.getpos('.')

  local srow, scol = s_pos[2], s_pos[3]
  local erow, ecol = e_pos[2], e_pos[3]
  e_pos = { erow, ecol }

  -- reverse condition; Visual mode moving up the buffer
  if srow > erow or (srow == erow and scol >= ecol) then
    srow, scol, erow, ecol = erow, ecol, srow, scol
  end

  if LAST_POS ~= nil then
    del_marked_ws(LAST_POS, e_pos)
  end

  LAST_POS = e_pos

  local text = api.nvim_buf_get_lines(0, srow - 1, erow, true)
  local text_i = 1

  for cur_row = srow, erow do
    -- gets the physical line, not the display line
    local line_text = text[text_i] .. nl_str

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

    text_i = text_i + 1
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
