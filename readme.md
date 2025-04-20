# 🔎 visual-whitespace.nvim

Reveal whitespace characters in visual mode, similar to VSCode.

![vsws](https://github.com/user-attachments/assets/c61f985b-f6ef-4686-9be7-c145b30bb64f)

<sub>GIF: Highlighting white spaces in linewise, blockwise, and charwise visual modes.</sub>

## Installation and configuration

To install the plugin with the default settings using Lazy:

```lua
  {
    'mcauley-penney/visual-whitespace.nvim',
    config = true,
    event = "ModeChanged *:[vV\22]", -- optionally, lazy load on entering visual mode
    opts = {},
  }
```

`visual-whitespace` comes with the following options and defaults:

```lua
opts = {
  enabled = true,
  highlight = { link = "Visual", default = true },
  list_chars = {
    space = '·',
    tab = '→',
    nbsp = '␣',
  },
  fileformat_chars = {
    unix = '↲',
    mac = '←',
    dos = '↙',
  },
  ignore = {
    filetypes = {},
    buftypes = {}
  }
}
```

### Highlighting

`visual-whitespace` defines the `VisualNonText` highlight group. In the configuration (shown above), the settings you provide in `highlight` will constitute this highlight group. The highlight can also be set using Neovim's Lua API, allowing for color schemes to support visual-whitespace:

```lua
-- This can go in your color scheme or in your plugin config
vim.api.nvim_set_hl(0, "VisualNonText", { fg = "#5D5F71", bg = "#24282d"})
```

### Functions

visual-whitespace affords the following user-facing functions:

| Lua                                     | Description                                                      |
| --------------------------------------- | ---------------------------------------------------------------- |
| `require("visual-whitespace").toggle()` | Turn visual-whitespace.nvim off (toggles the `enabled` cfg flag) |

Use them in keymaps like:

```lua
init = function()
    vim.keymap.set({ 'n', 'v' }, "<leader>tw", require("visual-whitespace").toggle, {})
end
```

## Info

### Description

In VSCode, the `renderWhitespace` setting allows the user to choose how to display whitespace characters inside of the editor. There are a few different options, some of which Neovim also has. For example, you can choose to show whitespace all the time.

One option that Neovim does not have that VSCode does is the `selection` option. This option for `renderWhitespace`, inspired by Sublime, allows the user to [see only whitespace that is under the current selection](https://github.com/microsoft/vscode/issues/1477) and is currently the [default setting](https://code.visualstudio.com/docs/reference/default-settings).

This plugin provides this ability inside of Neovim's visual/mouse selections, allowing you to see specific areas of whitespace only when you want to.

### Features

![vsws-features](https://github.com/user-attachments/assets/af2dda8d-35c3-4841-8fd2-f1768b8f97f3)

<sub>GIF: Capturing tabs, non-breaking spaces, spaces, and line feed characters.</sub>

visual-whitespace captures:

- spaces
- tabs
- non-breaking spaces
- new line chars
  - `Note:` [VSCode does not have this feature](https://github.com/microsoft/vscode/issues/12223). Because it is ostensibly desirable to VSCode users and Neovim already allows this via the `eol` key of the `listchars` option, this plugin has chosen to implement it. We have also made decisions about what to display, again given that we cannot follow VSCode's example but also because of the desire to improve upon the default Neovim experience. Given this, this plugin displays a symbol indicating the current `fileformat`, e.g. `←` for `mac` and `↲` for `unix`, even though it is all just `\n` internally. This is a departure from Neovim's `listchars` option.

### Versions and support

| Branch     | Neovim Version Compatibility | Features                                                                              |
| ---------- | ---------------------------- | ------------------------------------------------------------------------------------- |
| compat-v10 | `<0.11`                      | - Charwise<br>- Linewise                                                              |
| main       | `>=0.11`                     | - Charwise<br>- Linewise<br>- Blockwise<br>- Redraw-time, viewport-aware highlighting |

- `compat-v10` will accept PRs as long as they are compatible with `Neovim < 0.11`, but the maintainer will not develop this branch
- `main` is the primary development branch

## Credit

- [This post on the Neovim subreddit](https://www.reddit.com/r/neovim/comments/1b1sv3a/function_to_get_visually_selected_text/), for some of the logic for the original implementation
- [aaron-p1/match-visual.nvim](https://github.com/aaron-p1/match-visual.nvim)
