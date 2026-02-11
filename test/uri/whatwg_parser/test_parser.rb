# frozen_string_literal: true

require "test_helper"

class URI::WhatwgParser::TestParserTest < Test::Unit::TestCase
  def test_percent_encode
    parser = URI::WhatwgParser.new
    assert_equal 'A', parser.percent_encode('A', [])
    assert_equal '%0A', parser.percent_encode("\n", ["\n"])
    assert_equal '%E3%81%82', parser.percent_encode('あ', [])
    assert_equal "%E2%89%A1", parser.percent_encode("≡", URI::WhatwgParser::USERINFO_PERCENT_ENCODE_SET)
    assert_equal "%E2%80%BD", parser.percent_encode("‽", URI::WhatwgParser::USERINFO_PERCENT_ENCODE_SET)
    sjis_encoded = parser.percent_encode('あ', [], Encoding::Shift_JIS)
    assert_equal '%82%A0', sjis_encoded
  end

  def test_encoding
    parser = URI::WhatwgParser.new
    result = parser.split("dummy://example.com/?a=あ", encoding: Encoding::SJIS)
    assert_equal "dummy", result[0]
    assert_equal "example.com", result[2]
    assert_equal "a=%E3%81%82", result[7]
  end
end
