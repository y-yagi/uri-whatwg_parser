# frozen_string_literal: true

require "test_helper"
require "json"

class URI::WhatwgParser::TestURLTest < Test::Unit::TestCase
  urltestdata = JSON.load_file("test/resources/urltestdata.json")
  urltestdata.each do |testdata|
    next if testdata.is_a?(String)

    test_method_name = testdata["base"].nil? ? "test__#{testdata["input"]}" : "test__#{testdata["input"]}__#{testdata["base"]}"
    define_method test_method_name do
      parser = URI::WhatwgParser.new

      if testdata["failure"]
        assert_raise URI::WhatwgParser::ParseError do
          parser.split(testdata["input"], testdata["base"])
        end
      else
        ary = parser.split(testdata["input"], testdata["base"])
        parse_result = { scheme: ary[0], userinfo: ary[1], host: ary[2], port: ary[3], registry: ary[4], path: ary[5], opaque: ary[6], query: ary[7], fragment: ary[8]}
        assert_equal testdata["protocol"], parse_result[:scheme].to_s + ":", "[protocol]"
        assert_equal testdata["hostname"], parse_result[:host].to_s, "[hostname]"
        assert_equal testdata["port"], parse_result[:port].to_s, "[port]"
        assert_equal testdata["pathname"], parse_result[:path], "[pathname]" unless testdata["pathaname"] != "/"
        assert_equal testdata["hash"], "##{parse_result[:fragment]}", "[hash]" unless testdata["hash"].empty?
        assert_equal testdata["search"], "?#{parse_result[:query]}", "[search]" unless testdata["search"].empty?
        if !testdata["username"].empty? || !testdata["password"].empty?
          assert_equal "#{testdata["username"]}:#{testdata["password"]}", parse_result[:userinfo], "[username:password]"
        end
      end
    end
  end
end
