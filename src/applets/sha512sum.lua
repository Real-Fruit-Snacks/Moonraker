-- sha512sum: compute and check SHA-512 message digests.

local hashing = require("hashing")

return {
  name = "sha512sum",
  aliases = {},
  help = "compute and check SHA-512 message digests",
  main = function(argv)
    return hashing.run("sha512sum", "sha512", "SHA512", argv)
  end,
}
