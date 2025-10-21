# frozen_string_literal: true

require "test_helper"

class URI::WhatwgParser::TestParserTest < Test::Unit::TestCase
  def test_percent_encode
    parser = URI::WhatwgParser.new
    assert_equal 'A', parser.percent_encode('A', [])
    assert_equal '%0A', parser.percent_encode("\n", ["\n"])
    assert_equal '%E3%81%82', parser.percent_encode('あ', [])
    sjis_encoded = parser.percent_encode('あ', [], Encoding::Shift_JIS)
    assert_equal '%82%A0', sjis_encoded
  end

  def test_split
    parser = URI::WhatwgParser.new
    ary = parser.split("mailto:info@example.com")
    parse_result = { scheme: ary[0], userinfo: ary[1], host: ary[2], port: ary[3], registry: ary[4], path: ary[5], opaque: ary[6], query: ary[7], fragment: ary[8]}
    assert_equal "mailto", parse_result[:scheme]
    assert_equal "info@example.com", parse_result[:path]
  end
end
