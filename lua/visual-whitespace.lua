local uv = vim.uv
local v = vim
local api = v.api
local fn = v.fn

local M = {}
local NS = api.nvim_create_namespace("VisualWhitespace")
local HL = "VisualNonText"
local STATE = { user_enabled = true, active = false }

local WS = {
  [0x20] = true, -- space
  [0x09] = true, -- tab
  [0x0D] = true, -- carriage return
  [0xA0] = true, -- nbsp
}

local BIN_CACHE_KEY = "visual_whitespace_is_binary"
local BIN_CACHE_NAME = "visual_whitespace_bin_name"

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
  if name == "" then return false end

  local b = vim.b[bufnr]
  if b[BIN_CACHE_NAME] == name and b[BIN_CACHE_KEY] ~= nil then
    return b[BIN_CACHE_KEY]
  end

  local is_bin = file_has_nul(name) or false
  b[BIN_CACHE_NAME] = name
  b[BIN_CACHE_KEY] = is_bin
  return is_bin
end

local function is_allowed_ft_bt()
  return not CFG.ignore.filetypes[v.bo.filetype]
    and not CFG.ignore.buftypes[v.bo.buftype]
    and not is_binary_buf()
end

local function get_lead_and_trail_bounds(utf_start_pos_tbl, line)
  local n = #utf_start_pos_tbl
  if n == 0 then return 0, 0 end

  local lead_end = #line

  if CFG.match_types.lead then
    for i = 1, n do
      local codepoint = vim.fn.strgetchar(line, i - 1)
      if not WS[codepoint] then
        lead_end = utf_start_pos_tbl[i] - 1
        break
      end
    end
  end

  local trail_start = 0
  if CFG.match_types.trail then
    for i = n, 1, -1 do
      local codepoint = vim.fn.strgetchar(line, i - 1)
      if not WS[codepoint] then
        trail_start = utf_start_pos_tbl[i] - 1
        break
      end
    end
  end

  return lead_end, trail_start
end

local function pick_glyph(char, col, lead_end, trail_start)
  if char ~= " " then
    if char == "\t" then return CFG.list_chars.tab end
    if char == "\u{00A0}" then return CFG.list_chars.nbsp end
    return nil
  end

  if col < lead_end and CFG.match_types.lead then return CFG.list_chars.lead end
  if col > trail_start and CFG.match_types.trail then
    return CFG.list_chars.trail
  end
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

local function make_range(s_row, s_col, e_row, e_col)
  local start_pos = vim.pos(s_row, s_col)
  local end_pos = vim.pos(e_row, e_col)
  return vim.range(start_pos, end_pos)
end

------- Extmark utilities
local function get_line_marks(bufnr, range, nl_char)
  local row = range.start.row
  local line = api.nvim_buf_get_lines(bufnr, row, row + 1, true)[1]

  local s_col = range.start.col
  local e_col = math.min(range.end_.col, #line)

  local utf_start_pos_tbl = vim.str_utf_pos(line)
  local lead_end, trail_start = 0, 0
  if CFG.match_types.lead or CFG.match_types.trail then
    lead_end, trail_start = get_lead_and_trail_bounds(utf_start_pos_tbl, line)
  end

  local marks = {}
  local n = #utf_start_pos_tbl

  for i = 1, n do
    local pos = utf_start_pos_tbl[i] - 1
    if s_col <= pos and pos <= e_col then
      local codepoint = vim.fn.strgetchar(line, i - 1)
      if WS[codepoint] then
        local char = vim.fn.nr2char(codepoint)
        local glyph = pick_glyph(char, pos, lead_end, trail_start)
        if glyph then
          marks[#marks + 1] = { row = row, col = pos, glyph = glyph }
        end
      end
    end
  end

  if e_col >= #line then
    marks[#marks + 1] = { row = row, col = #line, glyph = nl_char } -- EOL is col=#line
  end

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

  return true
end

local function provider_on_win(_, winid, _, topline, botline)
  if winid ~= api.nvim_get_current_win() then return false end

  local start_coords = fn.getpos("v")
  local end_coords = fn.getpos(".")
  local cur_range = make_range(
    start_coords[2] - 1,
    start_coords[3] - 1,
    end_coords[2] - 1,
    end_coords[3] - 1
  )

  local viewport = make_range(topline, 0, botline + 1, 0)

  if not vim.range.intersect(cur_range, viewport) then return false end

  selection = {}

  local region_tbl =
    fn.getregionpos(start_coords, end_coords, { type = fn.mode(1), eol = true })

  for _, region in ipairs(region_tbl) do
    local s = region[1]
    local e = region[2]

    local s_row, s_col = s[2] - 1, s[3] - 1
    local e_row, e_col = e[2] - 1, e[3] - 1

    local cur_row_range = make_range(s_row, s_col, e_row, e_col)

    local row = cur_row_range.start.row
    selection[row] = cur_row_range
  end

  return true
end

local function provider_on_line(_, winid, bufnr, lnum0)
  if winid ~= api.nvim_get_current_win() then return end
  if not api.nvim_buf_is_valid(bufnr) then return end

  local row = lnum0

  local range = selection[row]
  if not range then return end

  local ff = v.bo[bufnr].fileformat
  local nl_glyph = CFG.fileformat_chars[ff] or CFG.fileformat_chars.unix

  local line_marks = get_line_marks(bufnr, range, nl_glyph)

  for _, mark in ipairs(line_marks) do
    api.nvim_buf_set_extmark(bufnr, NS, mark.row, mark.col, {
      virt_text = { { mark.glyph, HL } },
      virt_text_pos = "overlay",
      ephemeral = true,
    })
  end

  return true
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
