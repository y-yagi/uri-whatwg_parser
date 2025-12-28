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

  def test_encoding
    parser = URI::WhatwgParser.new
    result = parser.split("dummy://example.com/?a=あ", encoding: Encoding::SJIS)
    assert_equal "dummy", result[0]
    assert_equal "example.com", result[2]
    assert_equal "a=%E3%81%82", result[7]
  end
end
