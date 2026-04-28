-- true: do nothing, successfully (POSIX).

return {
  name = "true",
  aliases = {},
  help = "do nothing, successfully",
  main = function(_argv)
    return 0
  end,
}
