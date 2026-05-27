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
          parser.split(testdata["input"], base: testdata["base"])
        end
      else
        ary = parser.split(testdata["input"], base: testdata["base"])
        names = %i[scheme userinfo host port registry path opaque query fragment]
        parse_result = names.zip(ary).to_h
        assert_equal testdata["protocol"], parse_result[:scheme].to_s + ":", "[protocol]"
        assert_equal testdata["hostname"], parse_result[:host].to_s, "[hostname]"
        assert_equal testdata["port"], parse_result[:port].to_s, "[port]"
        assert_equal testdata["pathname"], parse_result[:path].to_s + parse_result[:opaque].to_s, "[pathname]" unless testdata["pathname"] == "/"
        assert_equal testdata["hash"], "##{parse_result[:fragment]}", "[hash]" unless testdata["hash"].empty?
        assert_equal testdata["search"], "?#{parse_result[:query]}", "[search]" unless testdata["search"].empty?
        user, password = parse_result[:userinfo].to_s.split(":", 2)
        assert_equal testdata["username"], user, "[username]" unless testdata["username"].empty?
        assert_equal testdata["password"], password, "[password]" unless testdata["password"].empty?

        # FIXME: `mailto:` is skipped because it contains processing that is incompatible with `uri` gem.
        return if testdata["protocol"] == "mailto:"
        # NOTE: URI::Generic#to_s doesn't set a port when it is the default port for the scheme, but WHATWG URL parser does set it.
        #       So skip the test when the scheme is "ldap:" and the port is the default port for LDAP.
        return if testdata["protocol"] == "ldap:" && testdata["port"].to_i == URI::LDAP::DEFAULT_PORT

        if testdata["base"]
          uri = URI.join(testdata["base"], testdata["input"])
        else
          uri = URI.parse(testdata["input"])
        end
        assert_equal testdata["href"], uri.to_s
      end
    end
  end
end
