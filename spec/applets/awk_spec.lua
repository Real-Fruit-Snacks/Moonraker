local helpers = require("helpers")

describe("awk applet", function()
  before_each(function() helpers.load_applets() end)

  it("requires a program", function()
    local rc = helpers.invoke_multicall("awk")
    assert.equal(2, rc)
  end)

  it("prints the whole record by default", function()
    local _, out = helpers.invoke_with_stdin("awk", "alpha\nbravo\n", "{print}")
    assert.equal("alpha\nbravo\n", out)
  end)

  it("prints a specific field", function()
    local _, out = helpers.invoke_with_stdin("awk",
      "first second third\nfoo bar baz\n", "{print $2}")
    assert.equal("second\nbar\n", out)
  end)

  it("BEGIN runs before input", function()
    local _, out = helpers.invoke_with_stdin("awk", "x\n",
      "BEGIN {print \"hi\"} {print $0}")
    assert.equal("hi\nx\n", out)
  end)

  it("END runs after input", function()
    local _, out = helpers.invoke_with_stdin("awk", "x\ny\n",
      "{ count++ } END { print count }")
    assert.equal("2\n", out)
  end)

  it("BEGIN/END without main runs once", function()
    local _, out = helpers.invoke_multicall("awk",
      "BEGIN { print \"hello\" }")
    assert.equal("hello\n", out)
  end)

  it("supports arithmetic + assignments", function()
    local _, out = helpers.invoke_multicall("awk",
      "BEGIN { x = 3; y = 4; print x + y; print x * y }")
    assert.equal("7\n12\n", out)
  end)

  it("string concat via juxtaposition", function()
    local _, out = helpers.invoke_multicall("awk",
      "BEGIN { print \"foo\" \"bar\" }")
    assert.equal("foobar\n", out)
  end)

  it("accumulates a sum", function()
    local _, out = helpers.invoke_with_stdin("awk",
      "1\n2\n3\n4\n", "{ sum += $1 } END { print sum }")
    assert.equal("10\n", out)
  end)

  it("filters by regex pattern", function()
    local _, out = helpers.invoke_with_stdin("awk",
      "apple\nbanana\nfig\ngrape\n", "/an/ { print }")
    assert.equal("banana\n", out)
  end)

  it("filters by expression pattern", function()
    local _, out = helpers.invoke_with_stdin("awk",
      "1\n5\n2\n8\n", "$1 > 3 { print }")
    assert.equal("5\n8\n", out)
  end)

  it("range patterns", function()
    local _, out = helpers.invoke_with_stdin("awk",
      "a\nstart\nb\nc\nend\nd\n", "/start/,/end/ { print }")
    assert.equal("start\nb\nc\nend\n", out)
  end)

  it("supports if/else", function()
    local _, out = helpers.invoke_multicall("awk",
      "BEGIN { if (3 > 2) print \"yes\"; else print \"no\" }")
    assert.equal("yes\n", out)
  end)

  it("supports while loops", function()
    local _, out = helpers.invoke_multicall("awk",
      "BEGIN { i = 0; while (i < 3) { print i; i++ } }")
    assert.equal("0\n1\n2\n", out)
  end)

  it("supports for(;;)", function()
    local _, out = helpers.invoke_multicall("awk",
      "BEGIN { for (i=1; i<=3; i++) print i*i }")
    assert.equal("1\n4\n9\n", out)
  end)

  it("supports for-in over arrays", function()
    local _, out = helpers.invoke_multicall("awk",
      "BEGIN { a[\"x\"]=1; a[\"y\"]=2; sum=0; "
      .. "for (k in a) sum += a[k]; print sum }")
    assert.equal("3\n", out)
  end)

  it("regex match operator", function()
    local _, out = helpers.invoke_multicall("awk",
      "BEGIN { if (\"hello\" ~ /ell/) print \"yes\" }")
    assert.equal("yes\n", out)
  end)

  it("regex not-match operator", function()
    local _, out = helpers.invoke_multicall("awk",
      "BEGIN { if (\"hello\" !~ /xyz/) print \"yes\" }")
    assert.equal("yes\n", out)
  end)

  it("custom field separator -F", function()
    local _, out = helpers.invoke_with_stdin("awk",
      "a:b:c\nx:y:z\n", "-F", ":", "{print $2}")
    assert.equal("b\ny\n", out)
  end)

  it("-v variable preset", function()
    local _, out = helpers.invoke_multicall("awk",
      "-v", "n=42", "BEGIN { print n }")
    assert.equal("42\n", out)
  end)

  it("printf works", function()
    local _, out = helpers.invoke_multicall("awk",
      "BEGIN { printf \"%-5s %d\\n\", \"x\", 7 }")
    assert.equal("x     7\n", out)
  end)

  it("length(string)", function()
    local _, out = helpers.invoke_multicall("awk",
      "BEGIN { print length(\"hello\") }")
    assert.equal("5\n", out)
  end)

  it("substr / index / toupper / tolower", function()
    local _, out = helpers.invoke_multicall("awk",
      "BEGIN { print substr(\"abcdef\", 2, 3); "
      .. "print index(\"abcdef\", \"cd\"); "
      .. "print toupper(\"hi\"); print tolower(\"YO\") }")
    assert.equal("bcd\n3\nHI\nyo\n", out)
  end)

  it("split sets array", function()
    local _, out = helpers.invoke_multicall("awk",
      "BEGIN { n = split(\"a,b,c\", arr, \",\"); "
      .. "print n, arr[1], arr[2], arr[3] }")
    assert.equal("3 a b c\n", out)
  end)

  it("gsub modifies in place", function()
    local _, out = helpers.invoke_multicall("awk",
      "BEGIN { s = \"hello\"; n = gsub(/l/, \"L\", s); print n, s }")
    assert.equal("2 heLLo\n", out)
  end)

  it("sub does only the first match", function()
    local _, out = helpers.invoke_multicall("awk",
      "BEGIN { s = \"hello\"; sub(/l/, \"L\", s); print s }")
    assert.equal("heLlo\n", out)
  end)

  it("NR, NF tracked correctly", function()
    local _, out = helpers.invoke_with_stdin("awk",
      "a b c\nx y\n", "{ print NR, NF }")
    assert.equal("1 3\n2 2\n", out)
  end)

  it("next skips to the next record", function()
    local _, out = helpers.invoke_with_stdin("awk",
      "skip\nkeep\nskip\n",
      "/skip/ { next } { print }")
    assert.equal("keep\n", out)
  end)

  it("exit returns code", function()
    local rc = helpers.invoke_with_stdin("awk", "x\n",
      "{ exit 7 }")
    assert.equal(7, rc)
  end)

  it("delete removes array entry", function()
    local _, out = helpers.invoke_multicall("awk",
      "BEGIN { a[\"x\"]=1; a[\"y\"]=2; delete a[\"x\"]; "
      .. "print (\"x\" in a), (\"y\" in a) }")
    assert.equal("0 1\n", out)
  end)

  it("$NF accesses last field", function()
    local _, out = helpers.invoke_with_stdin("awk",
      "a b c d\n", "{ print $NF }")
    assert.equal("d\n", out)
  end)

  it("OFS controls print separator", function()
    local _, out = helpers.invoke_with_stdin("awk",
      "a b c\n", "BEGIN{OFS=\":\"} { print $1, $2, $3 }")
    assert.equal("a:b:c\n", out)
  end)
end)
