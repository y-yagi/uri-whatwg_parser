# frozen_string_literal: true

class URI::WhatwgParser
  module ParserHelper
    C0_CONTROL_PERCENT_ENCODE_SET = (0..0x1f).map(&:chr)
    ASCII_ALPHA = ("a".."z").to_a + ("A".."Z").to_a
    ASCII_DIGIT = ("0".."9").to_a

    def ascii_alpha?(c)
      ASCII_ALPHA.include?(c)
    end

    def ascii_alphanumerica?(c)
      ascii_alpha?(c) || ascii_digit?(c)
    end

    def ascii_digit?(c)
      ASCII_DIGIT.include?(c)
    end

    def percent_encode(c, encode_set)
      return c unless encode_set.include?(c) || c.ord > 0x7e

      # For ASCII single-byte characters
      return "%%%02X" % c.ord if c.bytesize == 1

      c.bytes.map { |b| "%%%02X" % b }.join
    end
  end
end
