-- md5sum: compute and check MD5 message digests.

local hashing = require("hashing")

return {
  name = "md5sum",
  aliases = {},
  help = "compute and check MD5 message digests",
  main = function(argv)
    return hashing.run("md5sum", "md5", "MD5", argv)
  end,
}
