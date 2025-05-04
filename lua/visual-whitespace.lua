local v = vim
local api = v.api
local fn = v.fn

local M = {}
local NS = api.nvim_create_namespace("VisualWhitespace")
local HL = "VisualNonText"
local STATE = { user_enabled = true, active = false }

local NBSP = v.fn.nr2char(160)
local WS_RX = [[\v( |\t|\r|]] .. NBSP .. ")"

local CFG = {
  enabled = true,
  highlight = { link = "Visual", default = true },
  match_types = {
    space = true,
    tab = true,
    nbsp = true,
    lead = false,
    trail = false,
  },
  list_chars = {
    space = "·",
    tab = "↦",
    nbsp = "␣",
    lead = "‹",
    trail = "›",
  },
  fileformat_chars = {
    unix = "↲",
    mac = "←",
    dos = "↙",
  },
  ignore = { filetypes = {}, buftypes = {} },
}
local DEFAULT_CFG = v.deepcopy(CFG)

--------------------------------------------------------------------------------
-- Helper functions
--------------------------------------------------------------------------------

local function is_visual_mode()
  local m = fn.mode(1)
  return m == "v" or m == "V" or m == "\22"
end

local function is_allowed_ft_bt()
  local bufnr = api.nvim_get_current_buf()
  local ft = api.nvim_buf_get_option(bufnr, "filetype")
  local bt = api.nvim_buf_get_option(bufnr, "buftype")
  return not v.tbl_contains(DEFAULT_CFG.ignore.filetypes, ft)
    and not v.tbl_contains(DEFAULT_CFG.ignore.buftypes, bt)
end

local function lead_and_trail_bounds(line)
  local WS_FOR_BOUNDS = "[ \t\u{00A0}]"
  local _, last_lead_byte = line:find("^" .. WS_FOR_BOUNDS .. "*")
  local first_trail_byte = line:match("()" .. WS_FOR_BOUNDS .. "*$")
  local lead_end = 0
  local trail_start = math.huge

  if last_lead_byte and last_lead_byte > 0 then
    lead_end = v.str_utfindex(line, last_lead_byte) + 1
  end

  if first_trail_byte and first_trail_byte <= #line then
    trail_start = v.str_utfindex(line, first_trail_byte)
  end

  return lead_end, trail_start
end

local function pick_glyph(ch, col, lead_end, trail_start)
  local function fallback(type)
    if type then
      return DEFAULT_CFG.list_chars[type == DEFAULT_CFG.match_types.lead and "lead" or "trail"]
    elseif DEFAULT_CFG.match_types.space then
      return DEFAULT_CFG.list_chars.space
    end

    return nil
  end

  if ch ~= " " then
    return (ch == "\t" and DEFAULT_CFG.list_chars.tab)
      or (ch == "\u{00A0}" and DEFAULT_CFG.list_chars.nbsp)
      or nil
  end

  if col <= lead_end then return fallback(DEFAULT_CFG.match_types.lead) end
  if col >= trail_start then return fallback(DEFAULT_CFG.match_types.trail) end
  if DEFAULT_CFG.match_types.space then return DEFAULT_CFG.list_chars.space end

  return nil
end

local function read_opt_listchars()
  local lcs = v.opt.listchars:get()

  -- TODO: For 'tab' Vim allows two chars (e.g. "»·"); use the *first* for overlay.
  if lcs.tab and #lcs.tab > 1 then lcs.tab = v.fn.strcharpart(lcs.tab, 0, 1) end

  return {
    space = lcs.space,
    tab = lcs.tab,
    nbsp = lcs.nbsp,
    lead = lcs.lead,
    trail = lcs.trail,
  }
end

--------------------------------------------------------------------------------
-- Extmark utilities
--------------------------------------------------------------------------------

local function match_ws_pos(line, char_idx)
  local res = v.fn.matchstrpos(line, WS_RX, char_idx - 1)
  local s_char = tonumber(res[2])
  if s_char == -1 then return nil, nil end

  local match_text = res[1]
  return s_char + 1, match_text
end

local function get_marks(pos_list)
  local ff_chars = DEFAULT_CFG.fileformat_chars
  local bufnr = 0
  local ff = api.nvim_buf_get_option(bufnr, "fileformat")
  local nl_char = ff_chars[ff] or ff_chars.unix

  local s_row = pos_list[1][1][2]
  local e_row = pos_list[#pos_list][1][2]
  local lines = api.nvim_buf_get_lines(bufnr, s_row - 1, e_row, true)

  local marks = {}
  local match_char

  for _, range in ipairs(pos_list) do
    local row = range[1][2]
    local s_col = range[1][3]
    local e_col = range[2][3]

    local line = lines[row - s_row + 1] or ""

    local line_len = #line
    local visual_end = math.min(e_col, line_len)
    local lead_end, trail_start = lead_and_trail_bounds(line)

    local idx = s_col
    while idx <= visual_end do
      idx, match_char = match_ws_pos(line, idx)
      if not idx or idx > e_col then break end

      local glyph = pick_glyph(match_char, idx, lead_end, trail_start)
      if glyph then marks[#marks + 1] = { row, idx, glyph, "overlay" } end

      idx = idx + 1
    end

    if e_col > line_len then
      marks[#marks + 1] = { row, line_len + 1, nl_char, "overlay" }
    end
  end

  return marks
end

local function provider_on_win(_, _, bufnr, top, bot)
  if bufnr ~= api.nvim_get_current_buf() then return false end
  if not STATE.active or not is_visual_mode() then return false end

  local mode = fn.mode(1)
  local pos =
    fn.getregionpos(fn.getpos("v"), fn.getpos("."), { type = mode, eol = true })

  local slice = {}
  for _, line_range in ipairs(pos) do
    local row0 = line_range[1][2] - 1

    if row0 >= top and row0 <= bot then
      slice[#slice + 1] = line_range
    elseif row0 > bot then
      break
    end
  end

  if #slice == 0 then return true end

  for _, m in ipairs(get_marks(slice)) do
    api.nvim_buf_set_extmark(
      bufnr,
      NS,
      m[1] - 1,
      m[2] - 1,
      { virt_text = { { m[3], HL } }, virt_text_pos = m[4], ephemeral = true }
    )
  end
  return true
end

--------------------------------------------------------------------------------
-- Activation logic
--------------------------------------------------------------------------------

local function attach_provider()
  api.nvim_set_decoration_provider(NS, { on_win = provider_on_win })
end
local function detach_provider() api.nvim_set_decoration_provider(NS, {}) end

local function refresh()
  local now = STATE.user_enabled and is_allowed_ft_bt()
  if now == STATE.active then return end

  STATE.active = now
  if now then
    attach_provider()
  else
    detach_provider()
  end
end

function M.toggle()
  STATE.user_enabled = not STATE.user_enabled
  v.notify(
    ("[visual‑whitespace] %s"):format(
      STATE.user_enabled and "enabled" or "disabled"
    ),
    v.log.levels.INFO,
    { title = "visual‑whitespace" }
  )
  refresh()
end

function M.setup(user_cfg)
  local lcs_defaults = read_opt_listchars()

  DEFAULT_CFG =
    v.tbl_deep_extend("force", { list_chars = lcs_defaults }, CFG, user_cfg)

  STATE.user_enabled = DEFAULT_CFG.enabled

  api.nvim_set_hl(0, HL, DEFAULT_CFG.highlight)

  local grp = api.nvim_create_augroup("VisualWhitespaceCore", { clear = true })
  api.nvim_create_autocmd({ "BufEnter", "WinEnter", "FileType" }, {
    group = grp,
    callback = v.schedule_wrap(refresh),
  })
  api.nvim_create_autocmd("ColorScheme", {
    group = grp,
    callback = function() api.nvim_set_hl(0, HL, DEFAULT_CFG.highlight) end,
  })

  refresh()
end

return M
