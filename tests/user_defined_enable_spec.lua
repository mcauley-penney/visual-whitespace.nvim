local v = vim

describe("visual-whitespace public behaviour", function()
  local vw
  local buf
  local ns_id = v.api.nvim_create_namespace("VisualWhitespace")

  ----------------------------------------------------------------------------
  -- small helpers -----------------------------------------------------------
  ----------------------------------------------------------------------------
  local function fresh_test_buf()
    buf = v.api.nvim_create_buf(false, true)
    v.api.nvim_buf_set_lines(buf, 0, -1, true, { "foo bar" })
    v.api.nvim_set_current_buf(buf)

    v.bo.filetype = "lua"
    v.bo.buftype = ""

    v.opt.number = false
    v.opt.relativenumber = false
    v.opt.signcolumn = "no"
    v.opt.list = false
  end

  local function select_whole_line_visually()
    v.cmd("normal! gg")
    v.cmd("normal! v$")
    v.cmd("redraw!")
  end

  local function char_at_space()
    local code = v.fn.screenchar(1, 4)
    return v.fn.nr2char(code)
  end

  ----------------------------------------------------------------------------
  -- lifecycle ---------------------------------------------------------------
  ----------------------------------------------------------------------------
  before_each(function()
    package.loaded["visual-whitespace"] = nil
    vw = require("visual-whitespace")

    v.api.nvim_set_decoration_provider(ns_id, {})

    fresh_test_buf()
  end)

  ----------------------------------------------------------------------------
  -- assertions --------------------------------------------------------------
  ----------------------------------------------------------------------------
  it("renders overlay glyphs with default config (enabled = true)", function()
    vw.setup({})
    select_whole_line_visually()

    assert.are.equal("·", char_at_space())
  end)

  it("renders overlay glyphs when enabled = true", function()
    vw.setup({ enabled = true })
    select_whole_line_visually()

    assert.are.equal("·", char_at_space())
  end)

  it("does not render overlay glyphs when enabled = false", function()
    vw.setup({ enabled = false })
    select_whole_line_visually()

    assert.are.equal(" ", char_at_space())
  end)
end)
