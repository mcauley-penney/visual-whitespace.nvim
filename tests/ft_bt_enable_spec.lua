local v = vim

describe("filetype / buftype transitions", function()
  local vw
  local NS = v.api.nvim_create_namespace("VisualWhitespace")

  local function clean_ns() v.api.nvim_set_decoration_provider(NS, {}) end

  local function new_buf(lines, ft, bt)
    local b = v.api.nvim_create_buf(false, true)
    v.api.nvim_buf_set_lines(b, 0, -1, true, lines or { "foo bar" })
    v.api.nvim_set_current_buf(b)
    v.bo.filetype, v.bo.buftype = ft or "lua", bt or ""
    v.opt.number, v.opt.signcolumn, v.opt.list = false, "no", false
    return b
  end

  local function visual_select()
    v.cmd("normal! gg")
    v.cmd("normal! v$")
    v.cmd("redraw!")
  end

  local function screen_space()
    local code = v.fn.screenchar(1, 4)
    return code == 0 and "" or v.fn.nr2char(code)
  end

  before_each(function()
    clean_ns()
    package.loaded["visual-whitespace"] = nil
    vw = require("visual-whitespace")
    new_buf()
  end)

  it("activates when neither ft nor bt is ignored", function()
    vw.setup({
      ignore = { filetypes = { "markdown" }, buftypes = { "quickfix" } },
    })
    visual_select()
    assert.are.equal("·", screen_space())
  end)

  it("stays inactive when current ft is ignored", function()
    v.bo.filetype = "mytestft"
    vw.setup({ ignore = { filetypes = { "mytestft" } } })
    visual_select()
    assert.are.equal(" ", screen_space())
  end)

  it("stays inactive when current bt is ignored", function()
    v.bo.buftype = "nofile"
    vw.setup({ ignore = { buftypes = { "nofile" } } })
    visual_select()
    assert.are.equal(" ", screen_space())
  end)

  it("activates after switching from ignored bt to allowed bt", function()
    local ignored = "nofile"
    new_buf(nil, "lua", ignored)
    vw.setup({ ignore = { buftypes = { ignored } } })
    visual_select()
    assert.are.equal(" ", screen_space())

    new_buf(nil, "lua", "")

    -- flush Neovim's job queue with an event-loop turn
    vim.wait(0)
    visual_select()

    assert.are.equal("·", screen_space())
  end)

  it("activates after changing ft from ignored to allowed", function()
    local ignored = "markdown"
    v.bo.filetype = ignored
    vw.setup({ ignore = { filetypes = { ignored } } })
    visual_select()
    assert.are.equal(" ", screen_space())

    v.bo.filetype = "lua"

    -- flush Neovim's job queue with an event-loop turn
    vim.wait(0)
    v.cmd("redraw!")

    assert.are.equal("·", screen_space())
  end)
end)
