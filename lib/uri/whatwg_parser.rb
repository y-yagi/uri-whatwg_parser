# frozen_string_literal: true

require "set"
require "uri"
require_relative "whatwg_parser/error"
require_relative "whatwg_parser/version"
require_relative "whatwg_parser/parser_helper"
require_relative "whatwg_parser/host_parser"
require_relative "whatwg_parser/generic"

module URI
  class WhatwgParser
    include ParserHelper

    SPECIAL_SCHEME = { "ftp" => 21, "file" => nil, "http" => 80, "https" => 443, "ws" => 80, "wss" => 443 }

    FRAGMENT_PERCENT_ENCODE_SET = C0_CONTROL_PERCENT_ENCODE_SET | Set[" ", "\"", "<", ">", "`"]
    QUERY_PERCENT_ENCODE_SET = C0_CONTROL_PERCENT_ENCODE_SET | Set[" ", "\"", "#", "<", ">"]
    SPECIAL_QUERY_PERCENT_ENCODE_SET = QUERY_PERCENT_ENCODE_SET | Set["'"]
    PATH_PERCENT_ENCODE_SET = QUERY_PERCENT_ENCODE_SET | Set["?", "^", "`", "{", "}"]
    USERINFO_PERCENT_ENCODE_SET = PATH_PERCENT_ENCODE_SET | Set["/", ":", ";", "=", "@", "[", "\\", "]", "|"]

    SINGLE_DOT_PATH_SEGMENTS = Set[".", "%2e", "%2E"]
    DOUBLE_DOT_PATH_SEGMENTS = Set["..", ".%2e", ".%2E", "%2e.", "%2e%2e", "%2e%2E", "%2E.", "%2E%2e", "%2E%2E"]

    WINDOWS_DRIVE_LETTER = Regexp.new("\\A([a-zA-Z][:|])\\z")
    NORMALIZED_WINDOWS_DRIVE_LETTER = Regexp.new("\\A([a-zA-Z][:])\\z")
    STARTS_WITH_WINDOWS_DRIVE_LETTER = Regexp.new("\\A([a-zA-Z][:|])(?:[/\\?#])?\\z")

    VALID_SIGNS_FOR_SCHEME = Set["+", "-", "."]
    DELIMITER_SIGNS = Set["/", "?", "#"]

    WS_SCHEMES = Set["ws", "wss"]

    def initialize
      reset
      @host_parser = HostParser.new
    end

    def regexp
      {}
    end

    def parse(input, base: nil, encoding: Encoding::UTF_8, url: nil, state_override: nil) # :nodoc:
      URI.for(*self.split(input, base: base, encoding: encoding, url: url, state_override: state_override))
    end

    def split(input, base: nil, encoding: Encoding::UTF_8, url: nil, state_override: nil) # :nodoc:
      reset
      @base = nil
      if base != nil
        ary = split(base, base: nil, encoding: encoding)
        @base = { scheme: ary[0], userinfo: ary[1], host: ary[2], port: ary[3], registry: ary[4], path: ary[5], opaque: ary[6], query: ary[7], fragment: ary[8]}
        @base_paths = @paths
        reset
      end

      if url
        raise ArgumentError, "bad argument (expected URI object)" unless url.is_a?(URI::Generic)
        @parse_result.merge!(url.component.zip(url.send(:component_ary)).to_h)
        @parse_result[:path] = nil
      end

      if state_override
        @state = state_override.to_sym
        @state_override = @state
        raise ArgumentError, "state override is invalid" if !state_override.to_s.end_with?("_state") || !respond_to?(@state_override, private: true)
      else
        raise ParseError, "uri can't be empty" if (input.nil? || input.empty?) && @base.nil?
      end

      @encoding = encoding
      @input = input.dup

      unless url
        @input.sub!(/\A[\u0000-\u0020]*/, "")
        @input.sub!(/[\u0000-\u0020]*\z/, "")
      end

      @input.delete!("\t\n\r")

      @pos = 0

      while @pos <= @input.length
        c = @input[@pos]
        ret = send(@state, c)
        break if ret == :terminate
        @pos += 1
      end

      @parse_result[:userinfo] = [@username, @password].compact.reject(&:empty?).join(":")
      @parse_result[:path] = "/#{@paths.join("/")}" if @paths && !@paths.empty?
      @parse_result.values
    end

    def join(*uris)
      return parse(uris[0]) if uris.size == 1

      base, input = uris.shift(2)
      uri = parse(input.to_s, base: base.to_s)
      uris.each do |input|
        uri = parse(input.to_s, base: uri.to_s)
      end

      uri
    end

    def encode_userinfo(str)
      str.each_char.with_object(+"") do |char, encoded|
        encoded << percent_encode(char, USERINFO_PERCENT_ENCODE_SET)
      end
    end

    private

    def reset
      @buffer = +""
      @at_sign_seen = nil
      @password_token_seen = nil
      @inside_brackets = nil
      @paths = nil
      @username = nil
      @password = nil
      @parse_result = { scheme: nil, userinfo: nil, host: nil, port: nil, registry: nil, path: nil, opaque: nil, query: nil, fragment: nil }
      @state_override = nil
      @state = :scheme_start_state
    end

    def scheme_start_state(c)
      if ascii_alpha?(c)
        @buffer << c.downcase
        @state = :scheme_state
      elsif @state_override.nil?
        @pos -= 1
        @state = :no_scheme_state
      else
        raise ParseError, "scheme is invalid value"
      end
    end

    def scheme_state(c)
      if ascii_alphanumerica?(c) || VALID_SIGNS_FOR_SCHEME.include?(c)
        @buffer << c.downcase
      elsif c == ":"
        if @state_override
          if (special_url? && !special_url?(@buffer)) ||
            (!special_url? && special_url?(@buffer)) ||
            ((includes_credentials? || !@parse_result[:port].nil?) && @buffer == "file") ||
            (@parse_result[:scheme] == "file" && @parse_result[:host]&.empty?)
            return :terminate
          end
        end

        @parse_result[:scheme] = @buffer

        if @state_override
          if SPECIAL_SCHEME.value?(@parse_result[:port].to_i)
            @parse_result[:port] = nil
          end
          return :terminate
        end

        @buffer = +""

        if @parse_result[:scheme] == "file"
          @state = :file_state
        elsif special_url? && !@base.nil? && @parse_result[:scheme] == @base[:scheme]
          @state = :special_relative_or_authority_state
        elsif special_url?
          @state = :special_authority_slashes_state
        elsif rest.start_with?("/")
          @state = :path_or_authority_state
          @pos += 1
        else
          @parse_result[:opaque] = ""
          @state = :opaque_path_state
        end
      elsif @state_override.nil?
        @buffer.clear
        @pos = -1
        @state = :no_scheme_state
      else
        raise ParseError, "parsing scheme failed"
      end
    end

    def no_scheme_state(c)
      raise ParseError, "scheme is missing" if @base.nil? || (!@base[:opaque].nil? && c != "#")

      if !@base[:opaque].nil? && c == "#"
        @parse_result[:scheme] = @base[:scheme]
        @paths = @base_paths
        @parse_result[:query] = @base[:query]
        @parse_result[:fragment] = nil
        @state = :fragment_state
      elsif @base[:scheme] != "file"
        @state = :relative_state
        @pos -= 1
      else
        @state = :file_state
        @pos -= 1
      end
    end

    def special_relative_or_authority_state(c)
      if c == "/" && rest.start_with?("/")
        @state = :special_authority_ignore_slashes_state
        @pos -= 1
      else
        @state = :relative_state
        @pos -= 1
      end
    end

    def path_or_authority_state(c)
      if c == "/"
        @state = :authority_state
      else
        @state = :path_state
        @pos -= 1
      end
    end

    def relative_state(c)
      @parse_result[:scheme] = @base[:scheme]
      if c == "/"
        @state = :relative_slash_state
      elsif special_url? && c == "\\"
        @state = :relative_slash_state
      else
        @username, @password = @base[:userinfo].split(":") if @base[:userinfo]
        @parse_result[:host] = @base[:host]
        @parse_result[:port] = @base[:port]
        @paths = @base_paths
        @parse_result[:query] = @base[:query]

        if c == "?"
          @parse_result[:query] = nil
          @state = :query_state
        elsif c == "#"
          @parse_result[:fragment] = nil
          @state = :fragment_state
        elsif !c.nil?
          @parse_result[:query] = nil
          shorten_url_path
          @state = :path_state
          @pos -= 1
        end
      end
    end

    def relative_slash_state(c)
      if special_url? && (c == "/" || c == "\\")
        @state = :special_authority_ignore_slashes_state
      elsif c == "/"
        @state = :authority_state
      else
        @username, @password = @base[:userinfo].split(":") if @base[:userinfo]
        @parse_result[:host] = @base[:host]
        @parse_result[:port] = @base[:port]
        @state = :path_state
        @pos -= 1
      end
    end

    def special_authority_slashes_state(c)
      if c == "/" && rest.start_with?("/")
        @state = :special_authority_ignore_slashes_state
        @pos += 1
      else
        @state = :special_authority_ignore_slashes_state
        @pos -= 1
      end
    end

    def special_authority_ignore_slashes_state(c)
      if c != "/" && c != "\\"
        @state = :authority_state
        @pos -= 1
      end
    end

    def authority_state(c)
      if c == "@"
        @buffer.prepend("%40") if @at_sign_seen
        @at_sign_seen = true
        @buffer.each_char do |char|
          if char == ":" && !@password_token_seen
            @password_token_seen = true
            next
          end

          encoded_char = percent_encode(char, USERINFO_PERCENT_ENCODE_SET, @encoding)

          if @password_token_seen
            @password = @password.to_s + encoded_char
          else
            @username = @username.to_s + encoded_char
          end
        end

        @buffer.clear
      elsif c.nil? || DELIMITER_SIGNS.include?(c) || (special_url? && c == "\\")
        raise ParseError, "host is missing" if @at_sign_seen && @buffer.empty?

        @pos -= (@buffer.size + 1)
        @buffer.clear
        @state = :host_state
      else
        @buffer << c
      end
    end

    def host_state(c)
      if @state_override && @parse_result[:scheme] == "file"
        @pos -= 1
        @state = :file_host_state
      elsif c == ":" && !@inside_brackets
        raise ParseError, "host is missing" if @buffer.empty?
        raise ParseError, "invalid host" if @state_override && @state_override == :hostname_state

        @parse_result[:host] = @host_parser.parse(@buffer, !special_url?)
        @buffer.clear
        @state = :port_state
      elsif c.nil? || DELIMITER_SIGNS.include?(c) || (special_url? && c == "\\")
        @pos -= 1
        if special_url? && @buffer.empty?
          raise ParseError, "host is missing"
        elsif @state_override && @buffer.empty? && (includes_credentials? || !@parse_result[:port].nil?)
          raise ParseError, "invalid host"
        else
          @parse_result[:host] = @host_parser.parse(@buffer, !special_url?)
          @buffer.clear
          @state = :path_start_state
          return :terminate if @state_override
        end
      else
        @inside_brackets = true if c == "["
        @inside_brackets = false if c == "]"
        @buffer << c
      end
    end

    def port_state(c)
      if ascii_digit?(c)
        @buffer << c
      elsif c.nil? || DELIMITER_SIGNS.include?(c) || (special_url? && c == "\\") || @state_override
        unless @buffer.empty?
          port = Integer(@buffer, 10)
          raise ParseError, "port is invalid value" if port < 0 || port > 65535
          if SPECIAL_SCHEME[@parse_result[:scheme]] == port
            @parse_result[:port] = nil
          else
            @parse_result[:port] = port
          end

          @buffer.clear
          return :terminate if @state_override
        end

        raise ParseError, "port is invalid value" if @state_override
        @state = :path_start_state
        @pos -= 1
      else
        raise ParseError, "port is invalid value"
      end
    end

    def file_state(c)
      @parse_result[:scheme] = "file"
      @parse_result[:host] = nil

      if c == "/" || c == "\\"
        @state = :file_slash_state
      elsif !@base.nil? && @base[:scheme] == "file"
        @parse_result[:host] = @base[:host]
        @parse_result[:query] = @base[:query]
        if c == "?"
          @parse_result[:query] = nil
          @state = :query_state
        elsif c == "#"
          @parse_result[:fragment] = nil
          @state = :fragment_state
        elsif !c.nil?
          @parse_result[:query] = nil
          if !starts_with_windows_drive_letter?(rest)
            shorten_url_path
          else
            @paths = nil
          end
          @state = :path_state
          @pos -= 1
        end
      else
        @state = :path_state
        @pos -= 1
      end
    end

    def file_slash_state(c)
      if c == "/" || c == "\\"
        @state = :file_host_state
      else
        if !@base.nil? && @base[:scheme] == "file"
          @parse_result[:host] = @base[:host]
          if !starts_with_windows_drive_letter?(rest) && @base_paths && normalized_windows_drive_letter?(@base_paths[0])
            if @paths.nil?
              @paths ||= []
              @paths[0] = @base_paths[0]
            end
          end
        end
        @state = :path_state
        @pos -= 1
      end
    end

    def file_host_state(c)
      if c.nil? || DELIMITER_SIGNS.include?(c) || (special_url? && c == "\\")
        @pos -= 1

        if !@state_override && windows_drive_letter?(@buffer)
          @state = :path_state
        elsif @buffer.empty?
          @parse_result[:host] = nil
          return :terminate if @state_override
          @state = :path_start_state
        else
          host = @host_parser.parse(@buffer, !special_url?)
          host = "" if host == "localhost"
          @parse_result[:host] = host
          return :terminate if @state_override
          @buffer.clear
          @state = :path_start_state
        end
      else
        @buffer << c unless c.nil?
      end
    end

    def path_start_state(c)
      if special_url?
        @pos -= 1 if c != "/" && c != "\\"
        @state = :path_state
      elsif !@state_override && c == "?"
        @state = :query_state
      elsif !@state_override && c == "#"
        @state = :fragment_state
      elsif c != nil
        @pos -= 1 if c != "/"
        @state = :path_state
      elsif @state_override && @parse_result[:host].nil?
        @paths ||= []
        @paths << ""
      end
    end

    def path_state(c)
      @paths ||= []

      if (c.nil? || c == "/") || (special_url? && c == "\\") || (!@state_override && (c == "?" || c == "#"))
        if double_dot_path_segments?(@buffer)
          shorten_url_path

          if c != "/" && !(special_url? && c == "\\")
            @paths << ""
          end
        elsif single_dot_path_segments?(@buffer) && c != "/" && !((special_url? && c == "\\"))
          @paths << ""
        elsif !single_dot_path_segments?(@buffer)
          if @parse_result[:scheme] == "file" && @paths.empty? && windows_drive_letter?(@buffer)
            @buffer[1] = ":"
          end

          @paths << @buffer
        end

        @buffer = +""

        if c == "?"
          @parse_result[:query] = nil
          @state = :query_state
        elsif c == "#"
          @parse_result[:frament] = nil
          @state = :fragment_state
        end
      else
        @buffer << percent_encode(c, PATH_PERCENT_ENCODE_SET, @encoding)
      end
    end

    def opaque_path_state(c)
      if c == "?"
        @parse_result[:query] = nil
        @state = :query_state
      elsif c == "#"
        @parse_result[:fragment] = nil
        @state = :fragment_state
      elsif c == " "
        if rest.start_with?("?", "#")
          @parse_result[:opaque] += "%20"
        else
          @parse_result[:opaque] += " "
        end
      elsif !c.nil?
        @parse_result[:opaque] += percent_encode(c, C0_CONTROL_PERCENT_ENCODE_SET, @encoding)
      end
    end

    def query_state(c)
      if @encoding != Encoding::UTF_8 && (!special_url? || WS_SCHEMES.include?(@parse_result[:scheme]))
        @encoding = Encoding::UTF_8
      end

      if c.nil? || (!@state_override && c == "#")
        query_percent_encode_set = special_url? ? SPECIAL_QUERY_PERCENT_ENCODE_SET : QUERY_PERCENT_ENCODE_SET
        encoded_query = +""
        @buffer.each_char do |char|
          encoded_query << percent_encode(char, query_percent_encode_set, @encoding)
        end
        @parse_result[:query] = encoded_query
        @buffer.clear
        @state = :fragment_state if c == "#"
      elsif !c.nil?
        @buffer << c
      end
    end

    def fragment_state(c)
      return if c.nil?
      @parse_result[:fragment] = @parse_result[:fragment].to_s + percent_encode(c, FRAGMENT_PERCENT_ENCODE_SET, @encoding)
    end

    def windows_drive_letter?(str)
      WINDOWS_DRIVE_LETTER.match?(str)
    end

    def starts_with_windows_drive_letter?(str)
      STARTS_WITH_WINDOWS_DRIVE_LETTER.match?(str)
    end

    def normalized_windows_drive_letter?(str)
      NORMALIZED_WINDOWS_DRIVE_LETTER.match?(str)
    end

    def special_url?(str = @parse_result[:scheme])
      SPECIAL_SCHEME.key?(str)
    end

    def single_dot_path_segments?(c)
      SINGLE_DOT_PATH_SEGMENTS.include?(c)
    end

    def double_dot_path_segments?(c)
      DOUBLE_DOT_PATH_SEGMENTS.include?(c)
    end

    def shorten_url_path
      return if @paths.nil?
      return if @parse_result[:scheme] == "file" && @paths.length == 1 && normalized_windows_drive_letter?(@paths.first)
      @paths.pop
    end

    def includes_credentials?
      !@parse_result[:userinfo].nil? || (@username && !@username.empty?) || (@password && !@password.empty?)
    end

    def rest
      @input[@pos+1..]
    end

    def convert_to_uri(uri)
      if uri.is_a?(URI::Generic)
        uri
      elsif uri = String.try_convert(uri)
        parse(uri)
      else
        raise ArgumentError,
          "bad argument (expected URI object or URI string)"
      end
    end
  end

  WHATWG_PARSER = URI::WhatwgParser.new
end

URI.send(:remove_const, :DEFAULT_PARSER) if defined?(URI::DEFAULT_PARSER)
URI::DEFAULT_PARSER = URI::WHATWG_PARSER
URI.parser = URI::DEFAULT_PARSER
