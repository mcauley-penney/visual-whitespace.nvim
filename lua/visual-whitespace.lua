local v           = vim
local api         = v.api
local fn          = v.fn
local str_find    = string.find
local str_sub     = string.sub
local str_rep     = string.rep

local M           = {}
local NS          = api.nvim_create_namespace('VisualWhitespace')
local HL          = 'VisualNonText'
local STATE       = { user_enabled = true, active = false }

local CHAR_LOOKUP = {}
local WS_CLASS    = '[ \t\194]'
local WS_RUN_PAT  = '()(' .. WS_CLASS .. '+)'

local CFG         = {
  enabled          = true,
  highlight        = { link = 'Visual', default = true },
  list_chars       = { space = '·', tab = '→', nbsp = '␣' },
  fileformat_chars = { unix = '↲', mac = '←', dos = '↙' },
  ignore           = { filetypes = {}, buftypes = {} },
}
local DEFAULT_CFG = v.deepcopy(CFG)


--------------------------------------------------------------------------------
-- Helper functions
--------------------------------------------------------------------------------
local function is_visual_mode()
  local m = fn.mode(1)
  return m == 'v' or m == 'V' or m == '\22'
end

local function is_allowed_ft_bt()
  local bufnr = api.nvim_get_current_buf()
  local ft = api.nvim_buf_get_option(bufnr, 'filetype')
  local bt = api.nvim_buf_get_option(bufnr, 'buftype')
  return not v.tbl_contains(DEFAULT_CFG.ignore.filetypes, ft)
      and not v.tbl_contains(DEFAULT_CFG.ignore.buftypes, bt)
end

local function get_marks(pos_list)
  if #pos_list == 0 then return {} end

  local fmt_map   = DEFAULT_CFG.fileformat_chars
  local bufnr     = 0
  local filefmt   = api.nvim_buf_get_option(bufnr, 'fileformat')
  local nl_char   = fmt_map[filefmt] or fmt_map.unix

  local start_row = pos_list[1][1][2]
  local end_row   = pos_list[#pos_list][1][2]
  local lines     = api.nvim_buf_get_lines(bufnr, start_row - 1, end_row, true)

  local marks     = {}

  for _, rg in ipairs(pos_list) do
    local row        = rg[1][2]
    local scol       = rg[1][3]
    local ecol       = rg[2][3]

    local line       = lines[row - start_row + 1] or ''
    local line_len   = #line
    local visual_end = math.min(ecol, line_len)

    local idx        = scol
    while idx <= visual_end do
      local s, e = str_find(line, WS_RUN_PAT, idx)
      if not s or s > visual_end then break end
      e                 = math.min(e, visual_end)

      local ch          = str_sub(line, s, s)
      local virt        = str_rep(CHAR_LOOKUP[ch] or CHAR_LOOKUP[' '], e - s + 1)
      marks[#marks + 1] = { row, s, virt, 'overlay' }

      idx               = e + 1
    end

    if ecol > line_len then
      marks[#marks + 1] = { row, line_len + 1, nl_char, 'overlay' }
    end
  end
  return marks
end

--------------------------------------------------------------------------------
-- Extmark utilities
--------------------------------------------------------------------------------
local function provider_on_win(_, _, bufnr, top, bot)
  if bufnr ~= api.nvim_get_current_buf() then return false end
  if not STATE.active or not is_visual_mode() then return false end

  local mode  = fn.mode(1)
  local pos   = fn.getregionpos(fn.getpos('v'), fn.getpos('.'), { type = mode, eol = true })

  local slice = {}
  for _, line_rg in ipairs(pos) do
    local row0 = line_rg[1][2] - 1
    if row0 >= top and row0 <= bot then
      slice[#slice + 1] = line_rg
    elseif row0 > bot then
      break
    end
  end
  if #slice == 0 then return true end

  for _, m in ipairs(get_marks(slice)) do
    api.nvim_buf_set_extmark(
      bufnr, NS, m[1] - 1, m[2] - 1,
      { virt_text = { { m[3], HL } }, virt_text_pos = m[4], ephemeral = true }
    )
  end
  return true
end

local function attach_provider() api.nvim_set_decoration_provider(NS, { on_win = provider_on_win }) end
local function detach_provider() api.nvim_set_decoration_provider(NS, {}) end

--------------------------------------------------------------------------------
-- Activation logic
--------------------------------------------------------------------------------
local function refresh()
  local now = STATE.user_enabled and is_allowed_ft_bt()
  if now == STATE.active then return end

  STATE.active = now
  if now then attach_provider() else detach_provider() end
end

function M.toggle()
  STATE.user_enabled = not STATE.user_enabled
  v.notify(
    ('[visual‑whitespace] %s'):format(STATE.user_enabled and 'enabled' or 'disabled'),
    v.log.levels.INFO, { title = 'visual‑whitespace' }
  )
  refresh()
end

function M.setup(user_cfg)
  DEFAULT_CFG        = v.tbl_deep_extend('force', {}, CFG, user_cfg or {})
  STATE.user_enabled = DEFAULT_CFG.enabled

  CHAR_LOOKUP        = {
    [' ']    = DEFAULT_CFG.list_chars.space,
    ['\t']   = DEFAULT_CFG.list_chars.tab,
    ['\194'] = DEFAULT_CFG.list_chars.nbsp,
  }

  api.nvim_set_hl(0, HL, DEFAULT_CFG.highlight)

  local grp = api.nvim_create_augroup('VisualWhitespaceCore', { clear = true })
  api.nvim_create_autocmd({ 'BufEnter', 'WinEnter', 'FileType' }, {
    group = grp,
    callback = v.schedule_wrap(refresh),
  })
  api.nvim_create_autocmd('ColorScheme', {
    group = grp,
    callback = function() api.nvim_set_hl(0, HL, DEFAULT_CFG.highlight) end,
  })

  refresh()
end

return M
