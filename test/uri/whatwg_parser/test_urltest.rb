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
        names = %i[scheme userinfo host port registry path opaque query fragment]
        parse_result = names.zip(ary).to_h
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
