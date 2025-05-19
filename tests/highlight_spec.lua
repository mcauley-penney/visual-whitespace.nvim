-- tests/highlight_spec.lua
local eq = assert.equals

local function load_startup()
  -- Loads plugin/visual_whitespace.lua (simulates Neovim's plugin loader)
  dofile(
    vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
      .. "/plugin/visual_whitespace.lua"
  )
end

local function trigger_colorscheme()
  if vim.api.nvim_exec_autocmds then
    vim.api.nvim_exec_autocmds("ColorScheme", { modeline = false })
  else
    vim.cmd("doautocmd ColorScheme")
  end
end

local function hl(name) -- tiny wrapper for `nvim_get_hl`
  return vim.api.nvim_get_hl(0, { name = name, link = true })
end

local function hex(s) -- "#ffaa00" → 0xffaa00 → 16755200
  return tonumber(s:gsub("^#", ""), 16)
end

describe("highlight precedence:", function()
  before_each(function()
    package.loaded["visual-whitespace"] = nil
    vim.g.visual_whitespace = nil
    pcall(vim.api.nvim_clear_autocmds, { group = "VisualWhitespaceCore" })
    vim.api.nvim_set_hl(0, "VisualNonText", {}) -- fully clear the group
  end)

  after_each(function() vim.api.nvim_set_hl(0, "VisualNonText", {}) end)

  it("links to 'Visual' when nothing is defined", function()
    load_startup()

    local h = hl("VisualNonText")
    eq("Visual", h.link)
  end)

  it("colorscheme wins over plugin default", function()
    load_startup()

    -- Simulate the colorscheme defining its own style
    vim.api.nvim_set_hl(0, "VisualNonText", { fg = "#ffaa00" })
    trigger_colorscheme()

    local h = hl("VisualNonText")
    eq(nil, h.link)
    eq(hex("#ffaa00"), h.fg)
  end)

  it("user-supplied highlight overrides colorscheme", function()
    vim.g.visual_whitespace = {
      highlight = { fg = "#ff5555" },
    }

    load_startup()

    local h = hl("VisualNonText")
    eq(nil, h.link)
    eq(hex("#ff5555"), h.fg)
  end)
end)
