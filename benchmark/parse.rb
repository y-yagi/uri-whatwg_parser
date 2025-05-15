require "benchmark/ips"
require "uri/whatwg_parser"

uri = "http://www.ruby-lang.org/"
whatwg_parser = URI::WhatwgParser.new
$VERBOSE = nil

Benchmark.ips do |x|
  x.report("WHATWG")  do
    URI::DEFAULT_PARSER = whatwg_parser
    URI.parse(uri)
  end

  x.report("RFC3986") do
    URI::DEFAULT_PARSER = URI::RFC3986_PARSER
    URI.parse(uri)
  end

  x.compare!
end
