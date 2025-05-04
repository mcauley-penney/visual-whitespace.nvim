# 🔎 visual-whitespace.nvim

Display white space characters in visual mode, like VSCode's `renderWhitespace: selection`.

![vsws](https://github.com/user-attachments/assets/c61f985b-f6ef-4686-9be7-c145b30bb64f)

<sub>GIF: Highlighting white spaces in linewise, blockwise, and charwise visual modes.</sub>

In VSCode, the `renderWhitespace` options allows the user to choose how to display white space characters inside of the editor. Setting this option to `selection` allows the user to [see only whitespace that is under the current selection](https://github.com/microsoft/vscode/issues/1477). This is currently VSCode's [default setting](https://code.visualstudio.com/docs/reference/default-settings).

## Features

![vsws-features](https://github.com/user-attachments/assets/af2dda8d-35c3-4841-8fd2-f1768b8f97f3)

<sub>GIF: Capturing tabs, non-breaking spaces, spaces, and line feed characters.</sub>

visual-whitespace captures:

- spaces
- tabs
- non-breaking spaces
- leading and trailing spaces
  - overrides the general spaces, like the default behavior of `:h listchars`
- fileformat-specific new lines
  - `Note:` [VSCode does not currently have support for any new line character display](https://github.com/microsoft/vscode/issues/12223). This plugins enhances [Vim's](https://github.com/vim/vim/issues/6119) and [Neovim's](https://github.com/neovim/neovim/issues/31173) existing new line character support by displaying new lines that are specific to the current fileformat.

## Installation

To install the plugin with the default settings using Lazy:

```lua
  {
    'mcauley-penney/visual-whitespace.nvim',
    config = true,
    event = "ModeChanged *:[vV\22]", -- optionally, lazy load on entering visual mode
    opts = {},
  }
```

## Configuration

### Method

You can configure `visual-whitespace` using either:

1. your plugin manager (e.g. lazy.nvim), or

```lua
opts = {
    -- your opts here ...
}
```

2. the `vim.g.visual_whitespace` global dictionary

```lua
 vim.g.visual_whitespace = {
     -- your opts here ...
 }
```

### Options and defaults

```lua
opts = {
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
```

### Highlighting

`visual-whitespace` defines the `VisualNonText` highlight group. You can set this via the plugin configuration or through Neovim's Lua API, which allows for color schemes to support visual-whitespace:

```lua
-- This can go in your color scheme or in your plugin config
vim.api.nvim_set_hl(0, "VisualNonText", { fg = "#5D5F71", bg = "#24282d"})
```

### Functions

visual-whitespace affords the following user-facing functions:

| Lua                                     | Description                              |
| --------------------------------------- | ---------------------------------------- |
| `require("visual-whitespace").toggle()` | enable or disable visual-whitespace.nvim |

Use them in keymaps like:

```lua
init = function()
    vim.keymap.set({ 'n', 'v' }, "<leader>tw", require("visual-whitespace").toggle, {})
end
```

## Versions and support

| Branch     | Neovim Version Compatibility | Modes Supported               | Characters Supported                                                        | Speed                          |
| ---------- | ---------------------------- | ----------------------------- | --------------------------------------------------------------------------- | ------------------------------ |
| main       | `>=0.11`                     | Charwise, linewise, blockwise | Spaces, leading spaces, trailing spaces, tabs, fileformat-specific newlines | Redraw-time, viewport-specific |
| compat-v10 | `<0.11`                      | Charwise, linewise            | Spaces, tabs, linefeeds (Unix newlines)                                     | Slow                           |

- `main` is the primary development branch. The documentation above is for this branch.
- `compat-v10` will accept PRs as long as they are compatible with `Neovim < 0.11`, but the maintainer will not develop this branch.
