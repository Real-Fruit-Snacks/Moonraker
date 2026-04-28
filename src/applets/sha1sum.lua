-- sha1sum: compute and check SHA-1 message digests.

local hashing = require("hashing")

return {
  name = "sha1sum",
  aliases = {},
  help = "compute and check SHA-1 message digests",
  main = function(argv)
    return hashing.run("sha1sum", "sha1", "SHA1", argv)
  end,
}
