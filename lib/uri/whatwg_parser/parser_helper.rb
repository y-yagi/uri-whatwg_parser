# frozen_string_literal: true

require "set"

class URI::WhatwgParser
  module ParserHelper
    # NOTE: This set isn't accurate, but it's OK now because greater than `0x7e` is checked inside a method.
    C0_CONTROL_PERCENT_ENCODE_SET = Set.new((0..0x1f).map(&:chr))

    def utf8_percent_encode(c, encode_set)
      return c unless encode_set.include?(c) || c.ord > 0x7e

      # For ASCII single-byte characters
      return "%%%02X" % c.ord if c.bytesize == 1

      c.bytes.map { |b| "%%%02X" % b }.join
    end

    ENCODE_REGEXES = {}
    private_constant :ENCODE_REGEXES

    def utf8_percent_encode_string(str, encode_set)
      regex = ENCODE_REGEXES[encode_set.object_id] ||= build_encode_regex(encode_set)
      str.gsub(regex) { |c|
        c.bytesize == 1 ? "%%%02X" % c.ord : c.bytes.map { |b| "%%%02X" % b }.join
      }
    end

    private

    def build_encode_regex(encode_set)
      chars = encode_set.map { |c| Regexp.escape(c) }.join
      Regexp.new("[#{chars}]|[^\x00-\x7e]")
    end
  end
end
