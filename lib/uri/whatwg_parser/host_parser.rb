# frozen_string_literal: true

require "uri/idna"
require "ipaddr"
require_relative "parser_helper"

class URI::WhatwgParser
  class HostParser
    include ParserHelper

    FORBIDDEN_HOST_CODE_POINT = ["\x00", "\t", "\x0a", "\x0d", " ", "#", "/", ":", "<", ">", "?", "@", "[", "\\", "]", "^", "|"]
    FORBIDDEN_DOMAIN_CODE_POINT = FORBIDDEN_HOST_CODE_POINT + C0_CONTROL + ["%"]

    def parse(input, opaque = false) # :nodoc:
      return if input&.empty?

      if input.start_with?("[")
        raise ParseError unless input.end_with?("]")
        return parse_ipv6(input)
      end

      return parse_opaque_host(input) if opaque

      domain = percent_decode(input)
      ascii_domain = URI::IDNA.whatwg_to_ascii(domain.force_encoding(Encoding::UTF_8))
      if ends_in_number?(ascii_domain)
        ipv4 = parse_ipv4(ascii_domain)
        return serialize_ipv4(ipv4)
      end

      raise ParseError if include_forbidden_domain_code_point?(ascii_domain)
      ascii_domain
    rescue URI::IDNA::Error, Encoding::CompatibilityError, ArgumentError => _e
      raise ParseError
    end

    private

    def parse_ipv4(host)
      parts = host.split(".")
      raise URI::WhatwgParser::ParseError if parts.size > 4
      numbers = []
      parts.each do |part|
        value, _validation_error = parse_ipv4_number(part)
        numbers << value
      end

      (numbers.size-1).times {|i| raise URI::WhatwgParser::ParseError if numbers[i] > 255 }

      raise ParseError if numbers.last >= 256 ** (5 - numbers.size)

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

    def parse_ipv6(host)
      "[#{IPAddr.new(host).to_s}]"
    rescue
      raise ParseError
    end

    def parse_opaque_host(host)
      raise ParseError if include_forbidden_host_code_point?(host)
      host.chars.map { |c| percent_encode(c, C0_CONTROL_PERCENT_ENCODE_SET) }.join
    end

    def percent_decode(str)
      str.gsub(/%[0-9A-Fa-f]{2}/) do |m|
        m[1..2].to_i(16).chr
      end
    rescue ArgumentError
      raise ParseError
    end

    def ends_in_number?(domain)
      parts = domain.split(".")
      return false if parts.size == 0

      last = parts.last
      return true if last.chars.all? { |c| ascii_digit?(c) }

      begin
        parse_ipv4_number(last)
      rescue ParseError
        return false
      end

      true
    end

    def parse_ipv4_number(str)
      raise ParseError if str&.empty?

      validation_error = false
      r = 10

      if str.size >= 2 && (str.start_with?("0x") || str.start_with?("0X"))
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
        raise ParseError
      end
    end

    def include_forbidden_domain_code_point?(str)
      str.chars.intersect?(FORBIDDEN_DOMAIN_CODE_POINT)
    end

    def include_forbidden_host_code_point?(str)
      str.chars.intersect?(FORBIDDEN_HOST_CODE_POINT)
    end
  end
end
