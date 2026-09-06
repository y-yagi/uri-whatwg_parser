# frozen_string_literal: true

require "uri/idna"
require_relative "parser_helper"

class URI::WhatwgParser
  class HostParser
    include ParserHelper

    FORBIDDEN_HOST_CODE_POINT = Set["\x00", "\t", "\x0a", "\x0d", " ", "#", "/", ":", "<", ">", "?", "@", "[", "\\", "]", "^", "|"].freeze
    FORBIDDEN_DOMAIN_CODE_POINT = FORBIDDEN_HOST_CODE_POINT | C0_CONTROL_PERCENT_ENCODE_SET | Set["%", "\x7f"].freeze
    FORBIDDEN_HOST_REGEX = Regexp.union(FORBIDDEN_HOST_CODE_POINT.to_a).freeze
    FORBIDDEN_DOMAIN_REGEX = Regexp.union(FORBIDDEN_DOMAIN_CODE_POINT.to_a).freeze

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
        numbers << parse_ipv4_number(part)
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
        piece_index += 1
        compress = piece_index
      end

      while i < chars.length
        raise ParseError, "invalid IPv6 format" if piece_index == 8

        if chars[i] == ":"
          raise ParseError, "invalid IPv6 format" if compress
          i += 1
          piece_index += 1
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
          raise ParseError, "invalid IPv6 format" if length == 0 || piece_index > 6

          piece_index = parse_embedded_ipv4(chars, i - length, address, piece_index)
          break
        end

        raise ParseError, "invalid IPv6 format" if length == 0

        address[piece_index] = value
        piece_index += 1

        if chars[i] == ":"
          i += 1
          raise ParseError, "invalid IPv6 format" unless chars[i]
        elsif chars[i]
          raise ParseError, "invalid IPv6 format"
        end
      end

      if compress
        expand_ipv6_compression(address, compress, piece_index)
      elsif piece_index != 8
        raise ParseError, "invalid IPv6 format"
      end

      compress_ipv6(address)
    end

    def parse_embedded_ipv4(chars, i, address, piece_index)
      numbers_seen = 0

      while i < chars.length
        if numbers_seen > 0
          raise ParseError, "invalid IPv6 format" unless chars[i] == "." && numbers_seen < 4
          i += 1
        end

        raise ParseError, "invalid IPv6 format" unless chars[i]&.match?(/[0-9]/)

        ipv4_piece = nil
        while chars[i]&.match?(/[0-9]/)
          number = chars[i].to_i
          if ipv4_piece.nil?
            ipv4_piece = number
          elsif ipv4_piece == 0
            raise ParseError, "invalid IPv6 format"
          else
            ipv4_piece = ipv4_piece * 10 + number
          end
          raise ParseError, "invalid IPv6 format" if ipv4_piece > 255
          i += 1
        end

        address[piece_index] = address[piece_index] * 256 + ipv4_piece
        numbers_seen += 1
        piece_index += 1 if numbers_seen == 2 || numbers_seen == 4
      end

      raise ParseError, "invalid IPv6 format" if numbers_seen != 4

      piece_index
    end

    def expand_ipv6_compression(address, compress, piece_index)
      swaps = piece_index - compress
      piece_index = 7

      while piece_index != 0 && swaps > 0
        address[piece_index], address[compress + swaps - 1] = address[compress + swaps - 1], address[piece_index]
        piece_index -= 1
        swaps -= 1
      end
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
      return false if domain.empty?

      if domain.end_with?(".")
        # Remove trailing dot and find the actual last segment
        domain_without_trailing = domain[0...-1]
        return false if domain_without_trailing.empty?

        last_dot = domain_without_trailing.rindex(".")
        last = last_dot ? domain_without_trailing[last_dot + 1..-1] : domain_without_trailing
      else
        # Find the last segment after the last dot
        last_dot = domain.rindex(".")
        last = last_dot ? domain[last_dot + 1..-1] : domain
      end

      return false if last.empty?
      return true if last.match?(/\A\d+\z/)

      if last.start_with?("0x", "0X")
        hex = last[2..-1] || ""
        return true if hex.empty? || hex.match?(/\A[0-9A-Fa-f]+\z/)
      end

      false
    end

    def parse_ipv4_number(str)
      raise ParseError, "invalid IPv4 format" if str&.empty?

      r = 10

      if str.size >= 2 && str.start_with?("0x", "0X")
        str = str[2..-1]
        r = 16
      elsif str.size >= 2 && str.start_with?("0")
        str = str[1..-1]
        r = 8
      end

      return 0 if str.empty?

      begin
        Integer(str, r)
      rescue ArgumentError
        raise ParseError, "invalid IPv4 format"
      end
    end

    def domain_to_ascii(domain)
      # If domain is already ASCII-only, lowercase, and doesn't contain punycode prefix
      # we can skip IDNA processing
      if domain.ascii_only? && domain == domain.downcase && !domain.include?("xn--")
        raise ParseError, "including invalid value in host" if include_forbidden_domain_code_point?(domain)
        raise ParseError, "host can't be empty" if domain.empty?
        return domain
      end

      begin
        ascii_domain = URI::IDNA.whatwg_to_ascii(domain.force_encoding(Encoding::UTF_8), be_strict: false)
      rescue URI::IDNA::Error, Encoding::CompatibilityError, ArgumentError
        raise ParseError, "invalid host value" unless domain.ascii_only?

        ascii_domain = domain.downcase
      end

      raise ParseError, "including invalid value in host" if include_forbidden_domain_code_point?(ascii_domain)
      raise ParseError, "host can't be empty" if ascii_domain.empty?

      ascii_domain
    end

    def include_forbidden_domain_code_point?(str)
      str.match?(FORBIDDEN_DOMAIN_REGEX)
    end

    def include_forbidden_host_code_point?(str)
      str.match?(FORBIDDEN_HOST_REGEX)
    end
  end
end
