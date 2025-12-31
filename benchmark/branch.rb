require "benchmark/ips"
require "uri/whatwg_parser"

$VERBOSE = nil

condition = `git name-rev --name-only HEAD`.strip
if RubyVM::RJIT.enabled?
  condition += " with RJIT"
end

Benchmark.ips do |x|
  x.report("parse #{condition}") do
    URI.parse("http://www.ruby-lang.org/")
  end

  x.report("parse(multibyte) #{condition}") do
    URI.parse("http://日本語.jp")
  end

  x.report("parse(long uri) #{condition}") do
    URI.parse("https://user:password@example.com/path/to/resource?query=string#fragment")
  end

  x.save!('/tmp/whatg_parse-benchmark')
  x.compare!
end
