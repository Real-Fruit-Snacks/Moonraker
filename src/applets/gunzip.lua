-- gunzip: decompress gzipped (.gz) files. Thin wrapper around gzip -d.

local gzip = require("applets.gzip")

return {
  name = "gunzip",
  aliases = {},
  help = "decompress gzipped (.gz) files",
  main = function(argv)
    local forwarded = { [0] = "gzip", "-d" }
    for i = 1, #argv do
      forwarded[i + 1] = argv[i]
    end
    return gzip.main(forwarded)
  end,
}
