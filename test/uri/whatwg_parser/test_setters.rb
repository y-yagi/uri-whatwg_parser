# frozen_string_literal: true

require "test_helper"
require "json"
require "set"

class URI::WhatwgParser::TestSetters < Test::Unit::TestCase
  SETTERS_TESTS_DATA = JSON.load_file("test/resources/setters_tests.json")

  setup do
    @parser = URI::WhatwgParser.new
  end

  def test_set_scheme
    SETTERS_TESTS_DATA["protocol"].each do |data|
      uri = @parser.parse(data["href"])
      (uri.scheme = data["new_value"]) rescue nil

      assert_equal data["expected"]["href"], uri.to_s, "href=#{data["expected"]["href"]}, new_value=#{data["new_value"]}"
      assert_equal data["expected"]["protocol"], "#{uri.scheme}:"
    end
  end

  def test_set_user
    SETTERS_TESTS_DATA["username"].each do |data|
      uri = @parser.parse(data["href"])
      (uri.user = data["new_value"]) rescue nil

      assert_equal data["expected"]["username"], uri.user.to_s
    end
  end

  def test_set_password
    SETTERS_TESTS_DATA["password"].each do |data|
      uri = @parser.parse(data["href"])
      (uri.password = data["new_value"]) rescue nil

      assert_equal data["expected"]["password"], uri.password.to_s
    end
  end

  def test_set_host
    skip_tests_by_comment = Set.new([
      "Port numbers are 16 bit integers, overflowing is an error. Hostname is still set, though.",
      "Anything other than ASCII digit stops the port parser in a setter but is not an error",
      "Port number is unchanged if not specified",
    ])

    SETTERS_TESTS_DATA["host"].each do |data|
      # FIXME: The exception is raised when a parse error occurs, but WHATWG URL Standard expects a partial update.
      next if skip_tests_by_comment.include?(data["comment"])

      uri = @parser.parse(data["href"])
      (uri.host = data["new_value"]) rescue nil

      assert_equal data["expected"]["href"], uri.to_s, "href=#{data["expected"]["href"]}, new_value=#{data["new_value"]}"
      if data["expected"]["port"].nil? || data["expected"]["port"].to_s.empty?
        assert_equal data["expected"]["host"], uri.host.to_s
      else
        assert_equal data["expected"]["host"], "#{uri.host}:#{uri.port}"
      end
    end
  end

  def test_set_port
    SETTERS_TESTS_DATA["port"].each do |data|
      uri = @parser.parse(data["href"])
      (uri.port = data["new_value"]) rescue nil

      assert_equal data["expected"]["href"], uri.to_s, "href=#{data["expected"]["href"]}, new_value=#{data["new_value"]}" if data["expected"]["href"]
      assert_equal data["expected"]["port"], uri.port.to_s
    end
  end

  def test_set_path
    SETTERS_TESTS_DATA["pathname"].each do |data|
      uri = @parser.parse(data["href"])
      # FIXME: In WHATWG URL standard, an opaque should be treated as a path, but it is being treated as opaque for compatibility reasons.
      if uri.opaque
        assert_raises(URI::InvalidURIError) do
          uri.path =  data["new_value"]
        end
      else
        (uri.path = data["new_value"]) rescue nil
        assert_equal data["expected"]["pathname"], uri.path.to_s
      end
    end
  end

  def test_set_userinfo
    uri = @parser.parse("https://example.com")
    uri.userinfo = "user:pass"
    assert_equal "user", uri.user
    assert_equal "pass", uri.password
  end

  def test_set_opaque
    uri = @parser.parse("mailto:user@example.com")
    assert_equal "user@example.com", uri.opaque

    uri.opaque = "newuser@example.com"
    assert_equal "newuser@example.com", uri.opaque

    uri = @parser.parse("http://example.com/path")
    assert_raises(URI::InvalidURIError) do
      uri.opaque = "newpath"
    end
  end
end
