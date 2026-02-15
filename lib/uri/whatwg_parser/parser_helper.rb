# frozen_string_literal: true

require "set"

class URI::WhatwgParser
  module ParserHelper
    # NOTE: This set isn't accurate, but it's OK now because greater than `0x7e` is checked inside a method.
    C0_CONTROL_PERCENT_ENCODE_SET = Set.new((0..0x1f).map(&:chr))

    def ascii_alphanumerica?(c)
      ascii_alpha?(c) || ascii_digit?(c)
    end

    def utf8_percent_encode(c, encode_set)
      return c unless encode_set.include?(c) || c.ord > 0x7e

      # For ASCII single-byte characters
      return "%%%02X" % c.ord if c.bytesize == 1

      c.bytes.map { |b| "%%%02X" % b }.join
    end

    def utf8_percent_encode_string(str, encode_set)
      str.chars.map { |c| utf8_percent_encode(c, encode_set) }.join
    end
  end
end
