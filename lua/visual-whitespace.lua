local v = vim
local api = v.api
local fn = v.fn
local aucmd = api.nvim_create_autocmd
local nvim_buf_set_extmark = api.nvim_buf_set_extmark
local nvim_buf_del_extmark = api.nvim_buf_del_extmark
local nvim_buf_get_extmarks = api.nvim_buf_get_extmarks

local M = {}
local NS_ID = api.nvim_create_namespace('VisualWhitespace')
local HL_AUGRP = api.nvim_create_augroup("VisualWhitespaceHL", { clear = true })
local CORE_AUGRP = api.nvim_create_augroup("VisualWhitespace", { clear = true })
local CHAR_LOOKUP = nil
local LAST_RANGE = nil
local NL_STRS = {
  unix = nil,
  mac = nil,
  dos = nil,
}
local HL = "VisualNonText"
local WS_PATTERN = "([ \194\t\r\n])"
local ACTIVE_TYPE = false
local CFG = {
  highlight = { link = "Visual", default = true },
  space_char = '·',
  tab_char = '→',
  unix_char = '↲',
  mac_char = '←',
  dos_char = '↙',
  nbsp_char = '␣',
  enabled = true,
  excluded = {
    filetypes = {},
    buftypes = {}
  }
}

local function in_visual(mode)
  return mode == 'v' or mode == 'V' or mode == '\22'
end

-- to expand, give (old_list, new_list)
-- to remove, give (new_list, old_list)
local function diff_pos_lists(old, new)
  local intervals_to_add = {}

  local old_len = #old
  local new_len = #new

  local i_old = 1
  local i_new = 1

  -- Handle new intervals added at the beginning of the list
  while i_new <= new_len and i_old <= old_len do
    local new_line = new[i_new][1][2]
    local old_line = old[i_old][1][2]

    if new_line < old_line then
      -- New interval added at the beginning
      table.insert(intervals_to_add, new[i_new])
      i_new = i_new + 1
    else
      break
    end
  end

  -- Now process intervals that are common to both lists
  while i_new <= new_len and i_old <= old_len do
    local new_interval = new[i_new]
    local old_interval = old[i_old]

    local new_line = new_interval[1][2]
    local old_line = old_interval[1][2]

    if new_line == old_line then
      -- Lines match; process expansions within the interval
      local new_start, new_end = new_interval[1], new_interval[2]
      local old_start, old_end = old_interval[1], old_interval[2]

      -- Check for expansion at the start
      if new_start[3] < old_start[3] then
        table.insert(intervals_to_add, {
          new_start,
          { new_start[1], new_start[2], old_start[3] - 1, new_start[4] }
        })
      end

      -- Check for expansion at the end
      if new_end[3] > old_end[3] then
        table.insert(intervals_to_add, {
          { old_end[1], old_end[2], old_end[3] + 1, old_end[4] },
          new_end
        })
      end

      i_new = i_new + 1
      i_old = i_old + 1
    elseif new_line < old_line then
      -- New interval added in between
      table.insert(intervals_to_add, new_interval)
      i_new = i_new + 1
    else
      -- Old interval removed; skip it
      i_old = i_old + 1
    end
  end

  -- Handle remaining intervals in new_list (if new intervals added at the end)
  while i_new <= new_len do
    table.insert(intervals_to_add, new[i_new])
    i_new = i_new + 1
  end

  return intervals_to_add
end

local function get_marks(pos_list)
  local ff = vim.bo.fileformat
  local nl_char = NL_STRS[ff]

  local s_row = pos_list[1][1][2]
  local e_row = pos_list[#pos_list][1][2]

  local text = vim.api.nvim_buf_get_lines(0, s_row - 1, e_row, true)

  local ws_marks = {}
  local cur_row, line_text, line_len, match_char, start_idx, end_idx

  for _, pos in ipairs(pos_list) do
    cur_row = pos[1][2]
    start_idx = pos[1][3]
    end_idx = pos[2][3]

    line_text = text[cur_row - s_row + 1]
    line_len = #line_text

    local visual_end = math.min(end_idx, line_len)

    repeat
      start_idx, _, match_char = string.find(line_text, WS_PATTERN, start_idx)

      if not start_idx or start_idx > end_idx then goto continue end

      table.insert(ws_marks, { cur_row, start_idx, CHAR_LOOKUP[match_char], "overlay" })

      start_idx = start_idx + 1
      ::continue::
    until not start_idx or start_idx > visual_end

    if end_idx > line_len then
      table.insert(ws_marks, { cur_row, line_len + 1, nl_char, "overlay" })
    end
  end

  return ws_marks
end

local function del_marks(pos)
  for _, pos_pair in ipairs(pos) do
    local s_pos = { pos_pair[1][2] - 1, pos_pair[1][3] - 1 }
    local e_pos = { pos_pair[2][2] - 1, pos_pair[2][3] - 1 }

    local marks = nvim_buf_get_extmarks(0, NS_ID, s_pos, e_pos, {})

    for _, mark_data in ipairs(marks) do
      nvim_buf_del_extmark(0, NS_ID, mark_data[1])
    end
  end
end

local function set_marks(mark_table)
  for _, mark_data in ipairs(mark_table) do
    nvim_buf_set_extmark(0, NS_ID, mark_data[1] - 1, mark_data[2] - 1, {
      virt_text = { { mark_data[3], HL } },
      virt_text_pos = mark_data[4],
    })
  end
end

local clear_hl_ns = function()
  LAST_RANGE = nil
  api.nvim_buf_clear_namespace(0, NS_ID, 0, -1)
end

local main = function()
  local mode = fn.mode()
  if not in_visual(mode) then
    return
  end

  local pos_list = fn.getregionpos(fn.getpos('v'), fn.getpos('.'), { type = mode, eol = true })

  if not LAST_RANGE then
    local marks = get_marks(pos_list)
    set_marks(marks)
  else
    local expand_pos_list = diff_pos_lists(LAST_RANGE, pos_list)
    local contract_pos_list = diff_pos_lists(pos_list, LAST_RANGE)

    if #expand_pos_list > 0 then
      local marks_to_add = get_marks(expand_pos_list)
      set_marks(marks_to_add)
    end

    if #contract_pos_list > 0 then
      del_marks(contract_pos_list)
    end
  end

  LAST_RANGE = pos_list
end

local function is_enabled_ft_bt()
  local bufnr = v.api.nvim_get_current_buf()
  local ft = v.api.nvim_buf_get_option(bufnr, "filetype")
  local bt = v.api.nvim_buf_get_option(bufnr, "buftype")

  local ft_list = CFG.excluded.filetypes or {}
  local bt_list = CFG.excluded.buftypes or {}

  return not v.tbl_contains(ft_list, ft) and not v.tbl_contains(bt_list, bt)
end

local function enable_highlighting()
  aucmd("ModeChanged", {
    group = HL_AUGRP,
    pattern = "*:[vV\22]",
    callback = function()
      if v.o.operatorfunc ~= "" then
        return
      end

      return main()
    end
  })

  aucmd("CursorMoved", {
    group = HL_AUGRP,
    callback = function()
      return v.schedule(main)
    end
  })

  aucmd("ModeChanged", {
    group = HL_AUGRP,
    pattern = "[vV\22]*:[^vV\22]*",
    callback = function()
      return clear_hl_ns()
    end
  })
end

local function disable_highlighting()
  clear_hl_ns()
  vim.api.nvim_clear_autocmds({ group = HL_AUGRP })
end

local function recompute_active()
  local active_now = CFG.enabled and is_enabled_ft_bt()
  if active_now == ACTIVE_TYPE then
    return
  end

  ACTIVE_TYPE = active_now
  if ACTIVE_TYPE then
    enable_highlighting()
    main()
  else
    disable_highlighting()
  end
end

M.toggle = function()
  CFG.enabled = not CFG.enabled

  if not CFG.enabled then
    disable_highlighting()
    v.notify("[visual-whitespace]: highlighting disabled", v.log.levels.INFO, { title = "visual-whitespace" })
  else
    recompute_active()
    v.notify("[visual-whitespace]: highlighting enabled", v.log.levels.INFO, { title = "visual-whitespace" })
  end
end

M.setup = function(user_cfg)
  CFG = v.tbl_extend('force', CFG, user_cfg or {})
  CHAR_LOOKUP = {
    [' '] = CFG['space_char'],
    ['\194'] = CFG['nbsp_char'],
    ['\t'] = CFG['tab_char'],
  }
  NL_STRS = {
    unix = CFG['unix_char'],
    mac = CFG['mac_char'],
    dos = CFG['dos_char']
  }

  api.nvim_set_hl(0, HL, CFG['highlight'])

  aucmd({ "BufEnter", "WinEnter", "FileType" }, {
    group = CORE_AUGRP,
    callback = vim.schedule_wrap(recompute_active),
  })

  aucmd({ "ColorScheme" }, {
    group = CORE_AUGRP,
    callback = function()
      api.nvim_set_hl(0, HL, CFG['highlight'])
    end
  })

  recompute_active()
end


return M
