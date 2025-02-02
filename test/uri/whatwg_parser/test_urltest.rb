# frozen_string_literal: true

require "test_helper"
require "json"

class URI::WhatwgParser::TestURLTest < Test::Unit::TestCase
  urltestdata = JSON.load_file("test/resources/urltestdata.json")
  urltestdata.each do |testdata|
    next if testdata.is_a?(String)
    next unless testdata["base"].nil?

    # TODO: There are valid cases, but uri-idna raises an error
    next if %w(http://../ http://./ http://foo.09.. http://!"$&'()*+,-.;=_`{}~/ wss://!"$&'()*+,-.;=_`{}~/).include?(testdata["input"])

    define_method "test__#{testdata["input"]}"do
      if testdata["failure"]
        assert_raise URI::WhatwgParser::ParseError do
          URI.parse(testdata["input"])
        end
      else
        parser = URI::WhatwgParser.new
        ary = parser.split(testdata["input"])
        parse_result = { scheme: ary[0], userinfo: ary[1], host: ary[2], port: ary[3], registry: ary[4], path: ary[5], opaque: ary[6], query: ary[7], fragment: ary[8]}
        assert_equal testdata["protocol"], parse_result[:scheme] + ":", "[protocol]"
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
