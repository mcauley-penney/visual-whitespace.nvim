# 🔎 visual-whitespace.nvim

Reveal whitespace characters in visual mode, similar to VSCode.

![visual-ws](https://github.com/mcauley-penney/visual-whitespace.nvim/assets/59481467/89157048-1975-409c-977c-2d3fb43852d8)

<sub>GIF: Highlighting in charwise-visual and linewise-visual</sub>


## Installation and configuration

To install it with the default settings using Lazy:

```lua
  {
   'mcauley-penney/visual-whitespace.nvim',
    config = true
  }
```

`visual-whitespace` comes with the following default settings:

```lua
    opts = {
     highlight = { link = 'Visual' },
     space_char = '·',
     tab_char = '→',
     nl_char = '↲',
     cr_char = '←'
    },
```

## Credit

- [This post on the Neovim subreddit](https://www.reddit.com/r/neovim/comments/1b1sv3a/function_to_get_visually_selected_text/), for doing a lot of the math for me
- [aaron-p1/match-visual.nvim](https://github.com/aaron-p1/match-visual.nvim)
