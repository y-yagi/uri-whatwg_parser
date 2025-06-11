# frozen_string_literal: true

require "test_helper"
require "json"

class URI::WhatwgParser::TestParserTest < Test::Unit::TestCase
  def test_parse
    uri = URI.parse("http://foo.com/posts?id=30&limit=5#time=1305298413")
    assert_equal "http", uri.scheme
    assert_equal "foo.com", uri.host
    assert_equal 80, uri.port
    assert_equal "/posts", uri.path
    assert_equal "id=30&limit=5", uri.query
    assert_equal "time=1305298413", uri.fragment
  end

  def test_join
    uri = URI.join("http://www.ruby-lang.org/")
    assert_equal uri.to_s, "http://www.ruby-lang.org/"

    uri = URI.join("http://www.ruby-lang.org/", "/ja/man-1.6/")
    assert_equal uri.to_s, "http://www.ruby-lang.org/ja/man-1.6/"

    uri = URI.join("http://www.ruby-lang.org/", "/ja/man-1.6/" "b")
    assert_equal uri.to_s, "http://www.ruby-lang.org/ja/man-1.6/b"
  end

  def test_percent_encode
    parser = URI::WhatwgParser.new
    assert_equal 'A', parser.percent_encode('A', [])
    assert_equal '%0A', parser.percent_encode("\n", ["\n"])
    assert_equal '%E3%81%82', parser.percent_encode('あ', [])
    sjis_encoded = parser.percent_encode('あ', [], Encoding::Shift_JIS)
    assert_equal '%82%A0', sjis_encoded
  end
end
