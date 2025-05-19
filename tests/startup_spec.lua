local spy = require("luassert.spy")

local function load_startup()
  dofile(
    vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
      .. "/plugin/visual_whitespace.lua"
  )
end

describe("startup:", function()
  local setup_spy, init_spy

  before_each(function()
    package.loaded["visual-whitespace"] = nil
    vim.g.visual_whitespace = nil

    local mod = require("visual-whitespace") -- lua/visual-whitespace.lua
    setup_spy = spy.on(mod, "setup")
    init_spy = spy.on(mod, "initialize")
  end)

  after_each(function()
    setup_spy:revert()
    init_spy:revert()
  end)

  it("initialize() when vim.g.visual_whitespace is nil", function()
    vim.g.visual_whitespace = nil
    load_startup()
    assert.spy(init_spy).was_called(1)
    assert.spy(setup_spy).was_not_called()
  end)

  it(
    "initialize() when vim.g.visual_whitespace is an invalid type",
    function()
      vim.g.visual_whitespace = 42
      load_startup()
      assert.spy(init_spy).was_called(1)
      assert.spy(setup_spy).was_not_called()
    end
  )

  it(
    "initialize() and setup() when vim.g.visual_whitespace is a table",
    function()
      vim.g.visual_whitespace = { enabled = false }
      load_startup()

      assert.spy(init_spy).was_called(1)
      assert.spy(setup_spy).was_called(1)
    end
  )

  it(
    "initialize() and setup() when vim.g.visual_whitespace is a function returning a table",
    function()
      vim.g.visual_whitespace = function()
        return { highlight = { link = "Error" } }
      end
      load_startup()

      assert.spy(init_spy).was_called(1)
      assert.spy(setup_spy).was_called(1)
    end
  )

  it(
    "initialize() and setup() when setup() is called manually",
    function()
      local mod = require("visual-whitespace")
      mod.setup({ enabled = true })

      assert.spy(init_spy).was_called(1)
      assert.spy(setup_spy).was_called(1)
    end
  )
end)
