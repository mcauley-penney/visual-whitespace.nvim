local uv = vim.uv
local v = vim
local api = v.api
local fn = v.fn

local M = {}
local NS = api.nvim_create_namespace("VisualWhitespace")
local HL = "VisualNonText"
local STATE = { user_enabled = true, active = false }

local WS_SPACE = 1
local WS_TAB = 2
local WS_CR = 3
local WS_NBSP = 4

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

  if v.bo[bufnr].binary then return true end

  local name = api.nvim_buf_get_name(bufnr)
  if name == "" then return false end

  local b = v.b[bufnr]
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

local function get_ws_kind(line, utf_start_pos_tbl, i, line_len)
  local start_byte = utf_start_pos_tbl[i]
  local first_byte = line:byte(start_byte)

  if first_byte == 0x20 then return WS_SPACE end
  if first_byte == 0x09 then return WS_TAB end
  if first_byte == 0x0D then return WS_CR end

  if first_byte == 0xC2 then
    local next_byte = utf_start_pos_tbl[i + 1] or (line_len + 1)
    if next_byte == start_byte + 2 and line:byte(start_byte + 1) == 0xA0 then
      return WS_NBSP
    end
  end

  return nil
end

local function get_lead_and_trail_bounds(
  utf_start_pos_tbl,
  line,
  line_len,
  match_lead,
  match_trail
)
  local n = #utf_start_pos_tbl
  if n == 0 then return 0, 1 end

  local lead_end = 0
  if match_lead then
    lead_end = line_len
    for i = 1, n do
      if not get_ws_kind(line, utf_start_pos_tbl, i, line_len) then
        lead_end = utf_start_pos_tbl[i] - 1
        break
      end
    end
  end

  local trail_start = line_len + 1
  if match_trail then
    trail_start = 1
    for i = n, 1, -1 do
      if not get_ws_kind(line, utf_start_pos_tbl, i, line_len) then
        trail_start = utf_start_pos_tbl[i]
        break
      end
    end
  end

  return lead_end, trail_start
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
local function marks_for_line(bufnr, row, s_col, e_col, nl_char)
  local line = api.nvim_buf_get_lines(bufnr, row - 1, row, true)[1] or ""
  local line_len = #line
  local match_types = CFG.match_types
  local list_chars = CFG.list_chars
  local match_space = match_types.space
  local match_lead = match_types.lead
  local match_trail = match_types.trail
  local space_glyph = list_chars.space
  local tab_glyph = list_chars.tab
  local nbsp_glyph = list_chars.nbsp
  local lead_glyph = list_chars.lead
  local trail_glyph = list_chars.trail

  local scan_end = math.min(e_col, line_len)
  local utf_start_pos_tbl = v.str_utf_pos(line)
  local lead_end, trail_start = 0, line_len + 1
  if match_lead or match_trail then
    lead_end, trail_start = get_lead_and_trail_bounds(
      utf_start_pos_tbl,
      line,
      line_len,
      match_lead,
      match_trail
    )
  end

  local marks = {}
  local n = #utf_start_pos_tbl

  for i = 1, n do
    local start_byte = utf_start_pos_tbl[i]
    local pos = start_byte

    if pos > scan_end then break end

    if s_col <= pos then
      local ws_kind = get_ws_kind(line, utf_start_pos_tbl, i, line_len)

      if ws_kind then
        local glyph
        if ws_kind == WS_SPACE then
          if match_lead and pos <= lead_end then
            glyph = lead_glyph
          elseif match_trail and pos > trail_start then
            glyph = trail_glyph
          elseif match_space then
            glyph = space_glyph
          end
        elseif ws_kind == WS_TAB then
          glyph = tab_glyph
        elseif ws_kind == WS_NBSP then
          glyph = nbsp_glyph
        end

        if glyph then marks[#marks + 1] = { row, pos, glyph } end
      end
    end
  end

  if e_col > line_len then marks[#marks + 1] = { row, line_len + 1, nl_char } end
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
  local ff_chars = CFG.fileformat_chars
  local nl_glyph = ff_chars[v.bo[bufnr].fileformat] or ff_chars.unix

  local line_marks = marks_for_line(bufnr, row, s_col, e_col, nl_glyph)
  for i = 1, #line_marks do
    local mark = line_marks[i]
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
