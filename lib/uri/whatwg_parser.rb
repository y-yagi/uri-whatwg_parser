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

    ASCII_ALPHA_LOWERCASE = Set.new(("a".."z").to_a)
    ASCII_ALPHA_UPPERCASE = Set.new(("A".."Z").to_a)
    ASCII_DIGIT = Set.new(("0".."9").to_a)

    def initialize
      reset
      @host_parser = HostParser.new
    end

    def regexp
      {}
    end

    def parse(input, base: nil, url: nil, state_override: nil) # :nodoc:
      URI.for(*self.split(input, base: base, url: url, state_override: state_override))
    end

    def split(input, base: nil, url: nil, state_override: nil) # :nodoc:
      reset
      @base = nil
      if base != nil
        ary = split(base, base: nil)
        @base = { scheme: ary[0], userinfo: ary[1], host: ary[2], port: ary[3], registry: ary[4], path: ary[5], opaque: ary[6], query: ary[7], fragment: ary[8]}
        @base_paths = @paths
        reset
      end

      if url
        raise ArgumentError, "bad argument (expected URI object)" unless url.is_a?(URI::Generic)
        @parse_result.merge!(url.component.zip(url.send(:component_ary)).to_h)
        @username = url.user
        @password = url.password
        @parse_result.delete(:userinfo)
      end

      if state_override
        @state = state_override.to_sym
        @state_override = @state
        raise ArgumentError, "state override is invalid" if !state_override.to_s.end_with?("_state") || !respond_to?(@state_override, private: true)
      else
        raise ParseError, "uri can't be empty" if (input.nil? || input.empty?) && @base.nil?
      end

      input = input.dup

      unless url
        remove_c0_control_or_space!(input)
      end

      input.delete!("\t\n\r") if /[\t\n\r]/.match?(input)

      @input_chars = input.chars
      input_chars_length = @input_chars.length
      @pos = 0

      while @pos <= input_chars_length
        dispatch_state(@input_chars[@pos])
        break if @terminate
        @pos += 1
      end

      userinfo = [@username, @password].compact.reject(&:empty?).join(":")
      path = "/#{@paths.join("/")}" if @paths && !@paths.empty?
      [@parse_result[:scheme], userinfo, @parse_result[:host], @parse_result[:port], @parse_result[:registry], path, @parse_result[:opaque], @parse_result[:query], @parse_result[:fragment]]
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

    private

    def dispatch_state(c)
      case @state
      when :scheme_start_state                     then scheme_start_state(c)
      when :scheme_state                           then scheme_state(c)
      when :no_scheme_state                        then no_scheme_state(c)
      when :special_relative_or_authority_state    then special_relative_or_authority_state(c)
      when :path_or_authority_state                then path_or_authority_state(c)
      when :relative_state                         then relative_state(c)
      when :relative_slash_state                   then relative_slash_state(c)
      when :special_authority_slashes_state        then special_authority_slashes_state(c)
      when :special_authority_ignore_slashes_state then special_authority_ignore_slashes_state(c)
      when :authority_state                        then authority_state(c)
      when :host_state                             then host_state(c)
      when :port_state                             then port_state(c)
      when :file_state                             then file_state(c)
      when :file_slash_state                       then file_slash_state(c)
      when :file_host_state                        then file_host_state(c)
      when :path_start_state                       then path_start_state(c)
      when :path_state                             then path_state(c)
      when :opaque_path_state                      then opaque_path_state(c)
      when :query_state                            then query_state(c)
      when :fragment_state                         then fragment_state(c)
      end
    end

    def reset
      @buffer = +""
      @at_sign_seen = nil
      @password_token_seen = nil
      @inside_brackets = nil
      @paths = nil
      @username = nil
      @password = nil
      @parse_result = { scheme: nil, host: nil, port: nil, registry: nil, path: nil, opaque: nil, query: nil, fragment: nil }
      @state_override = nil
      @state = :scheme_start_state
      @special_url = nil
      @terminate = nil
    end

    def scheme_start_state(c)
      if ASCII_ALPHA_LOWERCASE.include?(c)
        @buffer << c
        @state = :scheme_state
      elsif ASCII_ALPHA_UPPERCASE.include?(c)
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
      if ASCII_ALPHA_LOWERCASE.include?(c) || ASCII_DIGIT.include?(c) || VALID_SIGNS_FOR_SCHEME.include?(c)
        @buffer << c
      elsif ASCII_ALPHA_UPPERCASE.include?(c)
        @buffer << c.downcase
      elsif c == ":"
        if @state_override
          if (special_url? && !special_url?(@buffer)) ||
            (!special_url? && special_url?(@buffer)) ||
            ((includes_credentials? || !@parse_result[:port].nil?) && @buffer == "file") ||
            (@parse_result[:scheme] == "file" && @parse_result[:host]&.empty?)
            @terminate = true
            return
          end
        end

        @parse_result[:scheme] = @buffer
        @special_url = special_url?(@buffer)

        if @state_override
          if SPECIAL_SCHEME.value?(@parse_result[:port].to_i)
            @parse_result[:port] = nil
          end
          @terminate = true
          return
        end

        @buffer = +""

        if @parse_result[:scheme] == "file"
          @state = :file_state
        elsif special_url? && !@base.nil? && @parse_result[:scheme] == @base[:scheme]
          @state = :special_relative_or_authority_state
        elsif special_url?
          @state = :special_authority_slashes_state
        elsif @input_chars[@pos + 1] == "/"
          @state = :path_or_authority_state
          @pos += 1
        else
          @parse_result[:opaque] = +""
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
        @special_url = special_url?(@base[:scheme])
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
      if c == "/" && @input_chars[@pos + 1] == "/"
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
      @special_url = special_url?(@base[:scheme])
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
      if c == "/" && @input_chars[@pos + 1] == "/"
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

          encoded_char = utf8_percent_encode(char, USERINFO_PERCENT_ENCODE_SET)

          if @password_token_seen
            (@password ||= +"") << encoded_char
          else
            (@username ||= +"") << encoded_char
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
          if @state_override
            @terminate = true
            return
          end
        end
      else
        @inside_brackets = true if c == "["
        @inside_brackets = false if c == "]"
        @buffer << c
      end
    end

    def port_state(c)
      if ASCII_DIGIT.include?(c)
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
          if @state_override
            @terminate = true
            return
          end
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
      @special_url = true
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
          if @state_override
            @terminate = true
            return
          end
          @state = :path_start_state
        else
          host = @host_parser.parse(@buffer, !special_url?)
          host = "" if host == "localhost"
          @parse_result[:host] = host
          if @state_override
            @terminate = true
            return
          end
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
        @buffer << utf8_percent_encode(c, PATH_PERCENT_ENCODE_SET)
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
        first_of_rest = @input_chars[@pos + 1]
        if first_of_rest == "?" || first_of_rest == "#"
          @parse_result[:opaque] << "%20"
        else
          @parse_result[:opaque] << " "
        end
      elsif !c.nil?
        @parse_result[:opaque] << utf8_percent_encode(c, C0_CONTROL_PERCENT_ENCODE_SET)
      end
    end

    def query_state(c)
      if c.nil? || (!@state_override && c == "#")
        query_percent_encode_set = special_url? ? SPECIAL_QUERY_PERCENT_ENCODE_SET : QUERY_PERCENT_ENCODE_SET
        # TODO: We need to consider encoding here.
        @parse_result[:query] = utf8_percent_encode_string(@buffer, query_percent_encode_set)
        @buffer.clear
        @state = :fragment_state if c == "#"
      elsif !c.nil?
        @buffer << c
      end
    end

    def fragment_state(c)
      return if c.nil?
      (@parse_result[:fragment] ||= +"") << utf8_percent_encode(c, FRAGMENT_PERCENT_ENCODE_SET)
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

    def special_url?(str = nil)
      if str
        SPECIAL_SCHEME.key?(str)
      else
        @special_url.nil? ? SPECIAL_SCHEME.key?(@parse_result[:scheme]) : @special_url
      end
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
      (@username && !@username.empty?) || (@password && !@password.empty?)
    end

    def rest
      @input_chars[@pos + 1..]&.join
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

    if RUBY_VERSION >= "4.0"
      def remove_c0_control_or_space!(str)
        if /[\u0000-\u0020]/.match?(str)
          str.strip!("\u0000-\u0020")
        end
      end
    else
      def remove_c0_control_or_space!(str)
        if /[\u0000-\u0020]/.match?(str)
          str.sub!(/\A[\u0000-\u0020]*/, "")
          str.sub!(/[\u0000-\u0020]*\z/, "")
        end
      end
    end
  end

  WHATWG_PARSER = URI::WhatwgParser.new
end

URI.send(:remove_const, :DEFAULT_PARSER) if defined?(URI::DEFAULT_PARSER)
URI::DEFAULT_PARSER = URI::WHATWG_PARSER
URI.parser = URI::DEFAULT_PARSER
