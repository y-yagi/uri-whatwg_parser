require "benchmark/ips"
require "uri/whatwg_parser"

uri = "http://www.ruby-lang.org/"
long_uri = "https://user:password@example.com/path/to/resource?query=string#fragment"
$VERBOSE = nil

Benchmark.ips do |x|
  x.report("WHATWG parse")  do
    URI::WHATWG_PARSER.parse(uri)
  end

  x.report("WHATWG parse(long uri)")  do
    URI::WHATWG_PARSER.parse(long_uri)
  end

  x.report("RFC3986 parse") do
    URI::RFC3986_PARSER.parse(uri)
  end

  x.report("RFC3986 parse(long uri)") do
    URI::RFC3986_PARSER.parse(long_uri)
  end

  x.compare!
end
