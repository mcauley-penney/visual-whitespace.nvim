# 🔎 visual-whitespace.nvim

Reveal whitespace characters in visual mode, similar to VSCode.

![vis-ws](https://github.com/user-attachments/assets/afa17c28-b5e3-4f4e-841c-0952975e7199)

<sub>GIF: Highlighting in linewise, charwise, and blockwise visual modes and playing nice with Treesitter incremental selection and [mini.move](https://github.com/echasnovski/mini.move)</sub>

## Versions and support

| Branch | Neovim Version Compatibility | Features                                                              |
| ------ | ---------------------------- | --------------------------------------------------------------------- |
| compat | `<0.11`                      | - Charwise<br>- Linewise                                              |
| main   | `>=0.11`                     | - Charwise<br>- Linewise<br>- Blockwise<br>- Incremental Highlighting |

- `compat` will receive bug fixes, documentation improvements, and new features from PRs as long as they are compatible with `Neovim < 0.11`, but the maintainer will not develop new features for this branch
- `main` is the primary development branch

See [here](https://gist.github.com/digitaljhelms/4287848) for more information on this convention.

## Installation and configuration

To install the plugin with the default settings using Lazy:

```lua
  {
    'mcauley-penney/visual-whitespace.nvim',
    config = true
    -- keys = { 'v', 'V', '<C-v>' }, -- optionally, lazy load on visual mode keys
  }
```

`visual-whitespace` comes with the following options and defaults:

```lua
    opts = {
      highlight = { link = "Visual" },
      space_char = '·',
      tab_char = '→',
      nl_char = '↲',
      cr_char = '←',
      enabled = true,
      excluded = {
        filetypes = {},
        buftypes = {}
      }
    },
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
    vim.keymap.set('n', "<leader>vw", require("visual-whitespace").toggle, {})
end
```

## Credit

- [This post on the Neovim subreddit](https://www.reddit.com/r/neovim/comments/1b1sv3a/function_to_get_visually_selected_text/), for the logic for the original implementation
- [aaron-p1/match-visual.nvim](https://github.com/aaron-p1/match-visual.nvim)
