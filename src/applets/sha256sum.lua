-- sha256sum: compute and check SHA-256 message digests.

local hashing = require("hashing")

return {
  name = "sha256sum",
  aliases = {},
  help = "compute and check SHA-256 message digests",
  main = function(argv)
    return hashing.run("sha256sum", "sha256", "SHA256", argv)
  end,
}
