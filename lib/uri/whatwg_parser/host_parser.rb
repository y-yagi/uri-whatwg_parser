# frozen_string_literal: true

require "uri/idna"
require_relative "parser_helper"

class URI::WhatwgParser
  class HostParser
    include ParserHelper

    FORBIDDEN_HOST_CODE_POINT = Set["\x00", "\t", "\x0a", "\x0d", " ", "#", "/", ":", "<", ">", "?", "@", "[", "\\", "]", "^", "|"]
    FORBIDDEN_DOMAIN_CODE_POINT = FORBIDDEN_HOST_CODE_POINT | C0_CONTROL_PERCENT_ENCODE_SET | Set["%", "\x7f"]

    def parse(input, opaque = false) # :nodoc:
      return "" if input&.empty?

      if input.start_with?("[")
        raise ParseError, "invalid IPv6 format" unless input.end_with?("]")
        return parse_ipv6(input)
      end

      return parse_opaque_host(input) if opaque

      domain = percent_decode(input)
      ascii_domain = domain_to_ascii(domain)
      if ends_in_number?(ascii_domain)
        ipv4 = parse_ipv4(ascii_domain)
        return serialize_ipv4(ipv4)
      end

      ascii_domain
    rescue URI::IDNA::Error, Encoding::CompatibilityError, ArgumentError => _e
      raise ParseError, "invalid host value"
    end

    private

    def parse_ipv4(host)
      parts = host.split(".")
      raise URI::WhatwgParser::ParseError, "invalid IPv4 format" if parts.size > 4
      numbers = []
      parts.each do |part|
        value, _validation_error = parse_ipv4_number(part)
        numbers << value
      end

      (numbers.size-1).times {|i| raise URI::WhatwgParser::ParseError, "invalid IPv4 format" if numbers[i] > 255 }

      raise ParseError, "invalid IPv4 format" if numbers.last >= 256 ** (5 - numbers.size)

      ipv4 = numbers.pop
      numbers.each_with_index do |number, index|
        ipv4 += number * (256 ** (3 - index))
      end

      ipv4
    end

    def serialize_ipv4(ipv4)
      output = []
      4.times.each do |_|
        output.prepend("#{ipv4 % 256}")
        ipv4 /= 256
      end

      output.join(".")
    end

    def parse_ipv6(input)
      input = input[1..-2] if input.start_with?("[") && input.end_with?("]")
      address = Array.new(8, 0)
      piece_index = 0
      compress = nil
      chars = input.chars
      i = 0

      if chars[i] == ":"
        raise ParseError, "invalid IPv6 format" unless chars[i + 1] == ":"
        i += 2
        compress = piece_index
      end

      while i < chars.length
        raise ParseError, "invalid IPv6 format" if piece_index == 8

        if chars[i] == ":"
          raise ParseError, "invalid IPv6 format" if compress
          i += 1
          compress = piece_index
          next
        end

        value = 0
        length = 0
        while length < 4 && i < chars.length && chars[i].match?(/[0-9A-Fa-f]/)
          value = value * 16 + chars[i].to_i(16)
          i += 1
          length += 1
        end

        if chars[i] == "."
          # IPv4-mapped address must be valid and complete, no trailing dot
          ipv4_piece = chars[i - length, chars.length - (i - length)].join
          parts = ipv4_piece.split(".")
          if parts.length != 4 || parts.any? { |p| p.empty? } || ipv4_piece.end_with?(".")
            raise ParseError, "invalid IPv6 format"
          end

          ipv4 = parse_ipv4(ipv4_piece)
          address[piece_index] = (ipv4 >> 16) & 0xFFFF
          address[piece_index + 1] = ipv4 & 0xFFFF
          piece_index += 2
          i = chars.length
          break
        end

        raise ParseError, "invalid IPv6 format" if length == 0

        address[piece_index] = value
        piece_index += 1

        if i < chars.length
          if chars[i] == ":"
            i += 1
          elsif chars[i] != nil
            raise ParseError, "invalid IPv6 format"
          end
        end
      end

      if compress
        swaps = piece_index - compress
        (0...swaps).each do |j|
          address[7 - j] = address[compress + swaps - 1 - j]
          address[compress + swaps - 1 - j] = 0
        end
      elsif piece_index != 8
        raise ParseError, "invalid IPv6 format"
      end

      compress_ipv6(address)
    end

    def compress_ipv6(address)
      # Find the longest run of zeros for '::' compression
      best_base = nil
      best_len = 0
      base = nil
      len = 0

      8.times do |idx|
        if address[idx] == 0
          base = idx if base.nil?
          len += 1
        else
          if len > best_len
            best_base = base
            best_len = len
          end
          base = nil
          len = 0
        end
      end

      if len > best_len
        best_base = base
        best_len = len
      end

      # Only compress if the run is at least two 0s
      if best_len < 2
        best_base = nil
      end

      # Build the string with '::' for the longest zero run
      result = []
      idx = 0
      while idx < 8
        if best_base == idx
          result << "" if idx == 0
          result << ""
          idx += best_len
          result << "" if idx == 8
          next
        end
        result << address[idx].to_s(16)
        idx += 1
      end

      "[#{result.join(":").gsub(/:{3,}/, "::")}]"
    end

    def parse_opaque_host(host)
      raise ParseError if include_forbidden_host_code_point?(host)
      host.chars.map { |c| utf8_percent_encode(c, C0_CONTROL_PERCENT_ENCODE_SET) }.join
    end

    def percent_decode(str)
      str.gsub(/%[0-9A-Fa-f]{2}/) do |m|
        m[1..2].to_i(16).chr
      end
    end

    def ends_in_number?(domain)
      parts = domain.split(".", -1)
      if parts.last == ""
        return false if parts.size == 1
        parts.pop
      end

      last = parts.last
      return true if last != "" && last.chars.all? { |c| ascii_digit?(c) }

      begin
        parse_ipv4_number(last)
      rescue ParseError
        return false
      end

      true
    end

    def parse_ipv4_number(str)
      raise ParseError, "invalid IPv4 format" if str&.empty?

      validation_error = false
      r = 10

      if str.size >= 2 && str.start_with?("0x", "0X")
        validation_error  = true
        str = str[2..-1]
        r = 16
      elsif str.size >= 2 && str.start_with?("0")
        validation_error  = true
        str = str[1..-1]
        r = 8
      end

      return 0, true if str.empty?

      begin
        output = Integer(str, r)
        return output, validation_error
      rescue ArgumentError
        raise ParseError, "invalid IPv4 format"
      end
    end

    def domain_to_ascii(domain)
      ascii_domain = URI::IDNA.whatwg_to_ascii(domain.force_encoding(Encoding::UTF_8), be_strict: false)

      raise ParseError, "including invalid value in host" if include_forbidden_domain_code_point?(ascii_domain)
      raise ParseError, "host can't be empty" if ascii_domain.empty?

      ascii_domain
    end

    def include_forbidden_domain_code_point?(str)
      FORBIDDEN_DOMAIN_CODE_POINT.any? {|c| str.include?(c) }
    end

    def include_forbidden_host_code_point?(str)
      FORBIDDEN_HOST_CODE_POINT.any? {|c| str.include?(c) }
    end
  end
end
