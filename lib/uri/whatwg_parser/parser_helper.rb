# frozen_string_literal: true

class URI::WhatwgParser
  module ParserHelper
    C0_CONTROL = (0..0x1f).to_a
    C0_CONTROL_PERCENT_ENCODE_SET = C0_CONTROL.map(&:chr)

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
      if encode_set.include?(c) || c.ord > 0x7e
        return c.unpack("C*").map { |b| sprintf("%%%02X", b) }.join
      end
      c
    end
  end
end
