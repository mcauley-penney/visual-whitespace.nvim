# visual-whitespace.nvim 🔎

Reveal whitespace characters in visual mode, similar to VSCode.

![vis-ws](https://github.com/mcauley-penney/visual-whitespace.nvim/assets/59481467/5d8b1e9a-e1b6-479a-b1d1-fcf0162fa4a8)

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
     nl_char = '↲'
    },
```

## Credit

- [This post on the Neovim subreddit](https://www.reddit.com/r/neovim/comments/1b1sv3a/function_to_get_visually_selected_text/), for doing a lot of the math for me
- [aaron-p1/match-visual.nvim](https://github.com/aaron-p1/match-visual.nvim)
