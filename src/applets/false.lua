-- false: do nothing, unsuccessfully (POSIX).

return {
  name = "false",
  aliases = {},
  help = "do nothing, unsuccessfully",
  main = function(_argv)
    return 1
  end,
}
