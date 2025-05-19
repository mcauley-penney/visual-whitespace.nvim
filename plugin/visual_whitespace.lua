local cfg = vim.g.visual_whitespace

if not cfg or (type(cfg) ~= "function" and type(cfg) ~= "table") then
  require("visual-whitespace").initialize()
  return
end

if type(cfg) == "table" then
  require("visual-whitespace").setup(cfg)
elseif type(cfg) == "function" then
  local ok, result = pcall(cfg)
  if ok and type(result) == "table" then
    require("visual-whitespace").setup(result)
  end
end
