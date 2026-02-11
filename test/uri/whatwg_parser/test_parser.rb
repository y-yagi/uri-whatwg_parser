# frozen_string_literal: true

require "test_helper"

class URI::WhatwgParser::TestParserTest < Test::Unit::TestCase
  def test_utf8_percent_encode
    parser = URI::WhatwgParser.new
    assert_equal 'A', parser.utf8_percent_encode('A', [])
    assert_equal '%0A', parser.utf8_percent_encode("\n", ["\n"])
    assert_equal '%E3%81%82', parser.utf8_percent_encode('あ', [])
    assert_equal "%E2%89%A1", parser.utf8_percent_encode("≡", URI::WhatwgParser::USERINFO_PERCENT_ENCODE_SET)
    assert_equal "%E2%80%BD", parser.utf8_percent_encode("‽", URI::WhatwgParser::USERINFO_PERCENT_ENCODE_SET)
  end

  def test_utf8_percent_encode_string
    parser = URI::WhatwgParser.new
    assert_equal "Say%20what%E2%80%BD", parser.utf8_percent_encode_string("Say what‽", URI::WhatwgParser::USERINFO_PERCENT_ENCODE_SET)
  end
end
