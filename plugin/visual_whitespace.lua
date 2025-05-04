local cfg = vim.g.visual_whitespace or {}

if type(cfg) == "function" then
  local ok, result = pcall(cfg)
  if ok and type(result) == "table" then
    cfg = result
  else
    cfg = {}
  end
end

require("visual-whitespace").setup(cfg)
