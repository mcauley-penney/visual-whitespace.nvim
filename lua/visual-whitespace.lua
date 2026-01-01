local uv = vim.uv
local v = vim
local api = v.api
local fn = v.fn

local M = {}
local NS = api.nvim_create_namespace("VisualWhitespace")
local HL = "VisualNonText"
local STATE = { user_enabled = true, active = false }

local NBSP = v.fn.nr2char(160)
local WS_RX = [[\v( |\t|\r|]] .. NBSP .. ")"
local BOUNDS_WS_RX = "[ \t\r\u{00A0}]"

local BASE_CFG = {
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
local CFG = v.deepcopy(BASE_CFG)

local region = {}
local selection = {}

------- Helper functions
local function as_set(list)
  local set = {}
  for _, val in ipairs(list or {}) do
    set[val] = true
  end
  return set
end

local function is_visual_mode()
  local m = fn.mode(1)
  return m == "v" or m == "V" or m == "\22"
end

local function file_has_nul(path)
  local fd = uv.fs_open(path, "r", 438)
  if not fd then return false end

  local chunk = uv.fs_read(fd, 8192, 0)
  uv.fs_close(fd)

  return chunk and chunk:find("\0", 1, true)
end

local function is_binary_buf()
  local bufnr = api.nvim_get_current_buf()

  if vim.bo[bufnr].binary then return true end

  local name = api.nvim_buf_get_name(bufnr)
  return name ~= "" and file_has_nul(name)
end

local function is_allowed_ft_bt()
  return not CFG.ignore.filetypes[v.bo.filetype]
    and not CFG.ignore.buftypes[v.bo.buftype]
    and not is_binary_buf()
end

local function lead_and_trail_bounds(line)
  if line:find("^" .. BOUNDS_WS_RX .. "*$") then
    return vim.str_utfindex(line, "utf-32", #line, false) + 1, math.huge
  end

  local _, last_lead_b = line:find("^" .. BOUNDS_WS_RX .. "*")
  local lead_end = last_lead_b
      and vim.str_utfindex(line, "utf-32", last_lead_b, false) + 1
    or 1

  local first_trail_b = line:match("()" .. BOUNDS_WS_RX .. "*$")
  local trail_start = first_trail_b
      and vim.str_utfindex(line, "utf-32", first_trail_b, false)
    or math.huge

  return lead_end, trail_start
end

local function pick_glyph(ch, col, lead_end, trail_start)
  local function fallback(type)
    if type then
      return CFG.list_chars[type == CFG.match_types.lead and "lead" or "trail"]
    elseif CFG.match_types.space then
      return CFG.list_chars.space
    end

    return nil
  end

  if ch ~= " " then
    return (ch == "\t" and CFG.list_chars.tab)
      or (ch == "\u{00A0}" and CFG.list_chars.nbsp)
      or nil
  end

  if col <= lead_end then return fallback(CFG.match_types.lead) end
  if col >= trail_start then return fallback(CFG.match_types.trail) end
  if CFG.match_types.space then return CFG.list_chars.space end

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

------- Extmark utilities
local function match_ws_pos(line, char_idx)
  local res = vim.F.npcall(v.fn.matchstrpos, line, WS_RX, char_idx - 1)
  if not res then return nil, nil end
  local s_char = tonumber(res[2])
  if s_char == -1 then return nil, nil end

  local match_text = res[1]
  return s_char + 1, match_text
end

local function marks_for_line(bufnr, row, s_col, e_col, nl_char)
  local line = api.nvim_buf_get_lines(bufnr, row - 1, row, true)[1] or ""
  local marks, idx = {}, s_col
  local lead_end, trail_start = lead_and_trail_bounds(line)
  local ch = nil

  while idx <= math.min(e_col, #line) do
    idx, ch = match_ws_pos(line, idx)
    if not idx or idx > e_col then break end
    local g = pick_glyph(ch, idx, lead_end, trail_start)
    if g then marks[#marks + 1] = { row, idx, g } end
    idx = idx + 1
  end

  if e_col > #line then marks[#marks + 1] = { row, #line + 1, nl_char } end
  return marks
end

local function provider_on_start()
  if
    not STATE.user_enabled
    or not is_visual_mode()
    or not is_allowed_ft_bt()
  then
    return false
  end

  local mode = fn.mode(1)
  region =
    fn.getregionpos(fn.getpos("v"), fn.getpos("."), { type = mode, eol = true })

  selection = {}
  for _, r in ipairs(region) do
    local row = r[1][2]
    local scol = r[1][3]
    local ecol = r[2][3]
    selection[row] = { scol, ecol }
  end
end

local function provider_on_win(_, winid, _, topline, botline)
  if winid ~= api.nvim_get_current_win() then return false end

  local row_min = region[1][1][2]
  local row_max = region[#region][2][2]

  if botline < row_min - 1 or topline > row_max - 1 then return false end
end

local function provider_on_line(_, winid, bufnr, lnum0)
  if winid ~= api.nvim_get_current_win() then return end
  if not api.nvim_buf_is_valid(bufnr) then return end

  local row = lnum0 + 1

  local range = selection[row]
  if not range then return end

  local s_col, e_col = range[1], range[2]
  local ff = v.bo[bufnr].fileformat
  local nl_glyph = CFG.fileformat_chars[ff] or CFG.fileformat_chars.unix

  for _, mark in ipairs(marks_for_line(bufnr, row, s_col, e_col, nl_glyph)) do
    api.nvim_buf_set_extmark(bufnr, NS, row - 1, mark[2] - 1, {
      virt_text = { { mark[3], HL } },
      virt_text_pos = "overlay",
      ephemeral = true,
    })
  end
end

------- initialization logic
function M.toggle()
  STATE.user_enabled = not STATE.user_enabled
  v.notify(
    ("[visual‑whitespace] %s"):format(
      STATE.user_enabled and "enabled" or "disabled"
    ),
    v.log.levels.INFO,
    { title = "visual‑whitespace" }
  )
end

function M.initialize()
  api.nvim_set_decoration_provider(NS, {
    on_start = provider_on_start,
    on_win = provider_on_win,
    on_line = provider_on_line,
  })

  local grp = api.nvim_create_augroup("VisualWhitespaceCore", { clear = true })

  api.nvim_create_autocmd("ColorScheme", {
    group = grp,
    callback = function() api.nvim_set_hl(0, HL, CFG.highlight) end,
  })

  v.api.nvim_set_hl(0, HL, CFG.highlight)
end

function M.setup(user_cfg)
  local lcs_defaults = read_opt_listchars()
  user_cfg = user_cfg or {}

  CFG = v.tbl_deep_extend(
    "force",
    { list_chars = lcs_defaults },
    BASE_CFG,
    user_cfg
  )

  CFG.ignore = {
    filetypes = as_set(CFG.ignore.filetypes),
    buftypes = as_set(CFG.ignore.buftypes),
  }

  CFG.highlight = user_cfg.highlight or CFG.highlight

  STATE.user_enabled = CFG.enabled

  M.initialize()
end

return M
