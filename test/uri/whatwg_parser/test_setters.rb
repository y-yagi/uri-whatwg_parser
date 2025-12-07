# frozen_string_literal: true

require "test_helper"
require "json"
require "set"

class URI::WhatwgParser::TestSetters < Test::Unit::TestCase
  methods_names = { "protocol" => "scheme=", "username" => "user=", "password" => "password=", "host" => "host=", "port" => "port=", "pathname" => "path=" }
  skip_tests_by_comment = Set.new([
    "Port is set to null if it is the default for new scheme.",
    "Port numbers are 16 bit integers, overflowing is an error. Hostname is still set, though.",
    "Anything other than ASCII digit stops the port parser in a setter but is not an error"
  ])

  setters_tests = JSON.load_file("test/resources/setters_tests.json")
  setters_tests.each do |setter_test|
    next unless methods_names.include?(setter_test[0])
    setter_method = methods_names[setter_test[0]]
    setter_test[1].each do |testdata|
      next if skip_tests_by_comment.include?(testdata["comment"])

      define_method("test_setter_#{setter_test[0]}__#{testdata["href"]}__#{testdata["new_value"]}") do
        uri = URI::WhatwgParser.new.parse(testdata["href"])
        return if setter_test[0] == "pathname" && uri.opaque
        uri.public_send(setter_method, testdata["new_value"]) rescue nil

        assert_equal testdata["expected"]["href"], uri.to_s if testdata["expected"]["href"] && !%w[username password pathname].include?(setter_test[0])

        case setter_test[0]
        when "protocol"
          assert_equal testdata["expected"]["protocol"], "#{uri.scheme}:"
        when "username"
          assert_equal testdata["expected"]["username"], uri.user.to_s
        when "password"
          assert_equal testdata["expected"]["password"], uri.password.to_s
        when "host"
          if testdata["expected"]["port"].nil? || testdata["expected"]["port"].to_s.empty?
            assert_equal testdata["expected"]["host"], uri.host.to_s
          else
            assert_equal testdata["expected"]["host"], "#{uri.host}:#{uri.port}"
          end
        when "port"
          unless URI::WhatwgParser::SPECIAL_SCHEME[uri.scheme] == uri.port
            assert_equal testdata["expected"]["port"], uri.port.to_s
          end
        when "pathname"
          assert_equal testdata["expected"]["pathname"], uri.path.to_s
        end
      end
    end
  end
end
