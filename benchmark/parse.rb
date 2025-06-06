require "benchmark/ips"
require "uri/whatwg_parser"

uri = "http://www.ruby-lang.org/"
long_uri = "https://user:password@example.com/path/to/resource?query=string#fragment"
whatwg_parser = URI::WhatwgParser.new
$VERBOSE = nil

Benchmark.ips do |x|
  x.report("WHATWG")  do
    URI::DEFAULT_PARSER = whatwg_parser
    URI.parse(uri)
    URI.parse(long_uri)
  end

  x.report("RFC3986") do
    URI::DEFAULT_PARSER = URI::RFC3986_PARSER
    URI.parse(uri)
    URI.parse(long_uri)
  end

  x.compare!
end
