local api = vim.api
local fn = vim.fn
local aucmd = api.nvim_create_autocmd
local hl_augrp = api.nvim_create_augroup("VisualWhitespaceHL", { clear = true })
local core_augrp = api.nvim_create_augroup("VisualWhitespace", { clear = true })

local M = {}
local NS_ID = api.nvim_create_namespace('VisualWhitespace')
local CFG = {
  highlight = { link = "Visual" },
  space_char = '·',
  tab_char = '→',
  nl_char = '↲',
  cr_char = '←',
  enabled = true,
  excluded = {
    filetypes = {},
    buftypes = {}
  }
}
local CHAR_LOOKUP


local function get_normalized_pos_list(mode)
  local pos_list = fn.getregionpos(fn.getpos('v'), fn.getpos('.'), { type = mode, eol = true })

  for _, pos in ipairs(pos_list) do
    if pos[1][4] > 0 then
      local new_pos = pos[1][3] + pos[1][4]
      pos[1][3] = new_pos
      pos[2][3] = new_pos
    end
  end

  return pos_list
end

local function get_marks(pos_list)
  local ff = vim.bo.fileformat
  local nl_str = ff == 'unix' and '\n' or ff == 'mac' and '\r' or '\r\n'

  local s_row = pos_list[1][1][2]
  local e_row = pos_list[#pos_list][1][2]

  local text = api.nvim_buf_get_lines(0, s_row - 1, e_row, true)

  for i = 1, #text do
    text[i] = table.concat({ text[i], nl_str })
  end

  local ws_marks = {}
  local cur_row, line_text, line_len, match_char, start_idx, end_idx

  for _, pos_pair in ipairs(pos_list) do
    cur_row = pos_pair[1][2]
    start_idx = pos_pair[1][3]
    end_idx = pos_pair[2][3]

    line_text = table.concat({ text[cur_row - s_row + 1], nl_str })
    line_len = #line_text

    if start_idx < line_len then
      repeat
        start_idx, _, match_char = string.find(line_text, "([ \t\r\n])", start_idx)

        if start_idx and start_idx <= end_idx then
          if ff == 'dos' and line_len == start_idx then
            table.insert(ws_marks, { cur_row, 0, CHAR_LOOKUP[match_char], "eol" })
          else
            table.insert(ws_marks, { cur_row, start_idx, CHAR_LOOKUP[match_char], "overlay" })
          end

          start_idx = start_idx + 1
        end
      until start_idx == nil or start_idx > end_idx
    end
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

local conduct_ws_highlight = function()
  local cur_mode = fn.mode()

  if cur_mode ~= 'v' and cur_mode ~= 'V' and cur_mode ~= '\22' then
    return
  end

  clear_ws_hl()

  local pos_list = get_normalized_pos_list(cur_mode)

  local marks = get_marks(pos_list)

  apply_marks(marks)
end

local function is_disabled_ft_bt()
  local contains = vim.fn.has('nvim-0.10') == 1 and vim.list_contains or vim.tbl_contains

  local bufnr = vim.api.nvim_get_current_buf()
  local ft = vim.api.nvim_buf_get_option(bufnr, "filetype")
  local bt = vim.api.nvim_buf_get_option(bufnr, "buftype")

  local ft_list = CFG.excluded.filetypes or {}
  local bt_list = CFG.excluded.buftypes or {}

  return contains(ft_list, ft) or contains(bt_list, bt)
end

local function init_aucmds()
  if CFG.enabled then
    aucmd("ModeChanged", {
      group = hl_augrp,
      pattern = "*:[vV\22]",
      callback = function()
        if vim.o.operatorfunc ~= "" then
          return
        end

        return conduct_ws_highlight()
      end
    })

    aucmd("CursorMoved", {
      group = hl_augrp,
      callback = function()
        return vim.schedule(conduct_ws_highlight)
      end
    })

    aucmd("ModeChanged", {
      group = hl_augrp,
      pattern = "[vV\22]:[^vV\22]",
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
    ['\t'] = CFG['tab_char'],
    ['\n'] = CFG['nl_char'],
    ['\r'] = CFG['cr_char']
  }

  local global_highlight = api.nvim_get_hl(0, { name = 'VisualNonText' })
  if not vim.tbl_isempty(global_highlight) then
    api.nvim_set_hl(0, 'VisualNonText', global_highlight)
  else
    api.nvim_set_hl(0, 'VisualNonText', CFG['highlight'])
  end

  aucmd({ "BufEnter", "WinEnter" }, {
    group = core_augrp,
    callback = vim.schedule_wrap(function()
      local prev_enabled = CFG.enabled
      CFG.enabled = not is_disabled_ft_bt()

      if prev_enabled ~= CFG.enabled then
        init_aucmds()
      end
    end)
  })

  init_aucmds()
end


return M
