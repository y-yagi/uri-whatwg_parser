require "benchmark/ips"
require "uri/whatwg_parser"

whatwg_parser = URI::WhatwgParser.new
$VERBOSE = nil

condition = ""
if ENV["USE_STRSCAN"] == 'true'
  condition += " with strscan"
end
if RubyVM::YJIT.enabled?
  condition += " with YJIT"
end

Benchmark.ips do |x|
  x.report("parse #{condition}") do
    URI.parse("http://www.ruby-lang.org/")
  end

  x.save!('/tmp/whatg_parse-benchmark')
  x.compare!
end
