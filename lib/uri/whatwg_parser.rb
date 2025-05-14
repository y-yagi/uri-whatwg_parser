# frozen_string_literal: true

require "strscan"
require "uri"
require_relative "whatwg_parser/error"
require_relative "whatwg_parser/version"
require_relative "whatwg_parser/parser_helper"
require_relative "whatwg_parser/host_parser"

module URI
  class WhatwgParser
    include ParserHelper

    SPECIAL_SCHEME = { "ftp" => 21, "file" => nil, "http" => 80, "https" => 443, "ws" => 80, "wss" => 443 }
    ASCII_ALPHA = ("a".."z").to_a + ("A".."Z").to_a
    ASCII_DIGIT = ("0".."9").to_a

    FRAGMENT_PERCENT_ENCODE_SET = C0_CONTROL_PERCENT_ENCODE_SET + [" ", "\"", "<", ">", "`"]
    QUERY_PERCENT_ENCODE_SET = C0_CONTROL_PERCENT_ENCODE_SET + [" ", "\"", "#", "<", ">"]
    SPECIAL_QUERY_PERCENT_ENCODE_SET = QUERY_PERCENT_ENCODE_SET + ["'"]
    PATH_PERCENT_ENCODE_SET = QUERY_PERCENT_ENCODE_SET + ["?", "^", "`", "{", "}"]
    USERINFO_PERCENT_ENCODE_SET = PATH_PERCENT_ENCODE_SET + ["/", ":", ";", "=","@", "[", "\\", "]", "|"]

    SINGLE_DOT_PATH_SEGMENTS = [".", "%2e", "%2E"]
    DOUBLE_DOT_PATH_SEGMENTS = ["..", ".%2e", ".%2E", "%2e.", "%2e%2e", "%2e%2E", "%2E.", "%2E%2e", "%2E%2E"]

    WINDOWS_DRIVE_LETTER = Regexp.new("\\A([a-zA-Z][:|])\\z")
    NORMALIZED_WINDOWS_DRIVE_LETTER = Regexp.new("\\A([a-zA-Z][:])\\z")
    STARTS_WITH_wINDOWS_DRIVE_LETTER = Regexp.new("\\A([a-zA-Z][:|])(?:[/\\?#])?\\z")

    def initialize
      reset
      @host_parser = HostParser.new
    end

    def regexp
      {}
    end

    def parse(uri, base = nil) # :nodoc:
      reset
      URI.for(*self.split(uri, base))
    end

    def split(uri, base = nil) # :nodoc:
      @base = nil
      if base != nil
        ary = split(base)
        @base = { scheme: ary[0], userinfo: ary[1], host: ary[2], port: ary[3], registry: ary[4], path: ary[5], opaque: ary[6], query: ary[7], fragment: ary[8]}
        @base_paths = @paths
        reset
      end

      uri = uri.dup
      uri.gsub!(/\A[\u0000-\u0020]*/, "")
      uri.gsub!(/[\u0000-\u0020]*\z/, "")
      uri.delete!("\t")
      uri.delete!("\n")
      uri.delete!("\r")

      raise ParseError, "uri can't be empty" if uri.empty? && @base.nil?

      @scanner = StringScanner.new(uri)

      loop do
        c = @scanner.getch
        send("on_#{@state}", c)

        if @force_continue
          @force_continue = false
          next
        end

        break if c.nil? && @scanner.eos?
      end

      @parse_result[:userinfo] = "#{@username}:#{@password}" if !@username.nil? || !@password.nil?
      @parse_result[:path] = "/#{@paths.join("/")}" if !@paths.empty?

      @parse_result.values
    end

    def join(*uris)
      return parse(uris[0]) if uris.size == 1

      base, input = uris.shift(2)
      uri = parse(input.to_s, base.to_s)
      uris.each do |input|
        uri = parse(input.to_s, uri.to_s)
      end

      uri
    end

    private

    def reset
      @scanner = nil
      @buffer = +""
      @at_sign_seen = nil
      @password_token_seen = nil
      @inside_brackets = nil
      @paths = []
      @username = nil
      @password = nil
      @parse_result = { scheme: nil, userinfo: nil, host: nil, port: nil, registry: nil, path: nil, opaque: nil, query: nil, fragment: nil }
      @force_continue = false
      @state = :scheme_start_state
    end

    def on_scheme_start_state(c)
      if ascii_alpha?(c)
        @buffer += c.downcase
        @state = :scheme_state
      else
        if c.nil?
          @force_continue = true
        else
          @scanner.pos -= c.bytesize
        end
        @state = :no_scheme_state
      end
    end

    def on_scheme_state(c)
      if ascii_alphanumerica?(c) || ["+", "-", "."].include?(c)
        @buffer += c.downcase
      elsif c == ":"
        @parse_result[:scheme] = @buffer
        @buffer = +""

        if @parse_result[:scheme] == "file"
          @state = :file_state
        elsif special_url? && !@base.nil? && @parse_result[:scheme] == @base[:scheme]
          @state = :special_relative_or_authority_state
        elsif special_url?
          @state = :special_authority_slashes_state
        elsif @scanner.rest.start_with?("/")
          @state = :path_or_authority_state
          @scanner.pos += c.bytesize
        else
          @parse_result[:path] = ""
          @state = :opaque_path_state
        end
      else
        @buffer = +""
        decrease_pos(c)
        @state = :no_scheme_state
      end
    end

    def on_no_scheme_state(c)
      raise ParseError, "scheme is missing" if @base.nil? || !@base[:opaque].nil? && c != "#"

      if !@base[:opaque].nil? && c == "#"
        @parse_result[:scheme] = @base[:scheme]
        @parse_result[:path] = @base[:path]
        @parse_result[:query] = @base[:query]
        @parse_result[:fragment] = ""
        @state = :fragment_state
      elsif @base[:scheme] != "file"
        @state = :relative_state
        decrease_pos(c)
      else
        @state = :file_state
        decrease_pos(c)
      end
    end

    def on_special_relative_or_authority_state(c)
      if c == "/" && @scanner.rest.start_with?("/")
        @state = :special_authority_ignore_slashes_state
        decrease_pos(c)
      else
        @state = :relative_state
        decrease_pos(c)
      end
    end

    def on_path_or_authority_state(c)
      if c == "/"
        @state = :authority_state
      else
        @state = :path_state
        decrease_pos(c)
      end
    end

    def on_relative_state(c)
      @parse_result[:scheme] = @base[:scheme]
      if c == "/"
        @state = :relative_slash_state
      elsif special_url? && c == "\\"
        @state = :relative_slash_state
      else
        @parse_result[:userinfo] = @base[:userinfo]
        @parse_result[:host] = @base[:host]
        @parse_result[:port] = @base[:port]
        @parse_result[:path] = @base[:path]
        @parse_result[:query] = @base[:query]

        if c == "?"
          @parse_result[:query] = ""
          @state = :query_state
        elsif c == "#"
          @parse_result[:fragment] = ""
          @state = :fragment_state
        elsif !c.nil?
          @parse_result[:query] = nil
          shorten_url_path
          @state = :path_state
          @scanner.pos -= c.bytesize
        end
      end
    end

    def on_relative_slash_state(c)
      if special_url? && (c == "/" || c == "\\")
        @state = :special_authority_ignore_slashes_state
      elsif c == "/"
        @state = :authority_state
      else
        @parse_result[:userinfo] = @base[:userinfo]
        @parse_result[:host] = @base[:host]
        @parse_result[:port] = @base[:port]
        @state = :path_state
        decrease_pos(c)
      end
    end

    def on_special_authority_slashes_state(c)
      if c == "/" && @scanner.rest.start_with?("/")
        @state = :special_authority_ignore_slashes_state
        @scanner.pos += c.bytesize
      else
        @state = :special_authority_ignore_slashes_state
        decrease_pos(c)
      end
    end

    def on_special_authority_ignore_slashes_state(c)
      if c != "/" && c != "\\"
        @state = :authority_state
        decrease_pos(c)
      end
    end

    def on_authority_state(c)
      if c == "@"
        @buffer.prepend("%40") if @at_sign_seen
        @at_sign_seen = true
        @buffer.chars.each do |char|
          if char == ":" && !@password_token_seen
            @password_token_seen = true
            next
          end

          encoded_char = percent_encode(char, USERINFO_PERCENT_ENCODE_SET)

          if @password_token_seen
            @password = @password.to_s + encoded_char
          else
            @username = @username.to_s + encoded_char
          end
        end

        @buffer = +""
      elsif c.nil? || ["/", "?", "#"].include?(c) || (special_url? && c == "\\")
        raise ParseError, "host is missing" if @at_sign_seen && @buffer.empty?
        if c.nil?
          @force_continue = true
          @scanner.pos -= @buffer.bytesize
        else
          @scanner.pos -= (@buffer.bytesize + c.bytesize.to_i)
        end
        @buffer = +""
        @state = :host_state
      else
        @buffer << c
      end
    end

    def on_host_state(c)
      if c == ":" && !@inside_brackets
        raise ParseError, "host is missing" if @buffer.empty?

        @parse_result[:host] = @host_parser.parse(@buffer, !special_url?)
        @buffer = +""
        @state = :port_state
      elsif c.nil? || ["/", "?", "#"].include?(c) || (special_url? && c == "\\")
        decrease_pos(c)
        if special_url? && @buffer.empty?
          raise ParseError, "host is missing"
        else
          @parse_result[:host] = @host_parser.parse(@buffer, !special_url?)
          @buffer = +""
          @state = :path_start_state
        end
      else
        @inside_brackets = true if c == "["
        @inside_brackets = false if c == "]"
        @buffer += c
      end
    end

    def on_port_state(c)
      if ascii_digit?(c)
        @buffer += c
      elsif c.nil? || ["/", "?", "#"].include?(c) || (special_url? && c == "\\")
        unless @buffer.empty?
          begin
            port = Integer(@buffer, 10)
            raise ParseError, "port is invalid value" if port < 0 || port > 65535
            @parse_result[:port] = port unless SPECIAL_SCHEME[@parse_result[:scheme]] == port
          rescue ArgumentError
            raise ParseError, "port is invalid value"
          end

          @buffer = +""
        end

        @state = :path_start_state
        decrease_pos(c)
      else
        raise ParseError, "port is invalid value"
      end
    end

    def on_file_state(c)
      @parse_result[:scheme] = "file"
      @parse_result[:host] = ""

      if c == "/" || c == "\\"
        @state = :file_slash_state
      elsif !@base.nil? && @base[:scheme] == "file"
        @parse_result[:host] = @base[:host]
        @parse_result[:query] = @base[:query]
        if c == "?"
          @parse_result[:query] = ""
          @state = :query_state
        elsif c == "#"
          @parse_result[:fragment] = ""
          @state = :fragment_state
        elsif !c.nil?
          @parse_result[:query] = nil
          if !starts_with_windows_drive_letter?(@scanner.rest)
            shorten_url_path
          else
            @paths = []
          end
          @state = :path_state
          decrease_pos(c)
        end
      else
        @state = :path_state
        decrease_pos(c)
      end
    end

    def on_file_slash_state(c)
      if c == "/" || c == "\\"
        @state = :file_host_state
      else
        if !@base.nil? && @base[:scheme] == "file"
          @parse_result[:host] = @base[:host]
          if !starts_with_windows_drive_letter?(@scanner.rest) && normalized_windows_drive_letter?(@base_paths[0])
            @paths[0] += @base_paths[0]
          end
        end
        @state = :path_state
        decrease_pos(c)
      end
    end

    def on_file_host_state(c)
      if c.nil? || c == "/" || c == "\\" || c == "?" || c == "#"
        @scanner.pos -= c.bytesize unless c.nil?

        if windows_drive_letter?(@buffer)
          @state = :path_state
        elsif @buffer.empty?
          @parse_result[:host] = ""
          @state = :path_start_state
        else
          host = @host_parser.parse(@buffer, !special_url?)
          if host != "localhost"
            @parse_result[:host] = host
          end

          @buffer = +""
          @state = :path_start_state
        end
      end

      @buffer += c unless c.nil?
    end

    def on_path_start_state(c)
      return if c.nil?

      if special_url?
        @scanner.pos -= c.bytesize if c != "/" && c != "\\"
        @state = :path_state
      elsif c == "?"
        @state = :query_state
      elsif c == "#"
        @state = :fragment_state
      elsif c != nil
        @scanner.pos -= c.bytesize if c != "/"
        @state = :path_state
      end
    end

    def on_path_state(c)
      if (c.nil? || c == "/") || (special_url? && c == "\/") || (c == "?" || c == "#")

        if double_dot_path_segments?(@buffer)
          shorten_url_path
          if c != "/" || (special_url? && c == "\/")
            @paths << ""
          end
        elsif single_dot_path_segments?(@buffer) && (c != "/" || (special_url? && c == "\/"))
          @paths << ""
        elsif !single_dot_path_segments?(@buffer)
          if @parse_result[:scheme] == "file" && @paths.empty? && windows_drive_letter?(@buffer)
            @buffer[1] = ":"
          end
          @paths << @buffer
        end

        @buffer = +""

        if c == "?"
          @parse_result[:query] = ""
          @state = :query_state
        elsif c == "#"
          @parse_result[:frament] = ""
          @state = :fragment_state
        end
      else
        @buffer << percent_encode(c, PATH_PERCENT_ENCODE_SET)
      end
    end

    def on_opaque_path_state(c)
      if c == "?"
        @parse_result[:query] = ""
        @state = :query_state
      elsif c == "#"
        @parse_result[:fragment] = ""
        @state = :fragment_state
      elsif c == " "
        if @scanner.rest.start_with?("?") || @scanner.rest.start_with?("#")
          @parse_result[:path] = @parse_result[:path].to_s + "%20"
        else
          @parse_result[:path] = @parse_result[:path].to_s + " "
        end
      elsif !c.nil?
        @parse_result[:path] = @parse_result[:path].to_s + percent_encode(c, C0_CONTROL_PERCENT_ENCODE_SET)
      end
    end

    def on_query_state(c)
      if c.nil? || c == "#"
        query_percent_encode_set = special_url? ? SPECIAL_QUERY_PERCENT_ENCODE_SET : QUERY_PERCENT_ENCODE_SET
        @parse_result[:query] = @buffer.chars.map { |c| percent_encode(c, query_percent_encode_set) }.join
        @buffer = +""
        @state = :fragment_state if c == "#"
      elsif !c.nil?
        @buffer << c
      end
    end

    def on_fragment_state(c)
      return if c.nil?
      @parse_result[:fragment] = @parse_result[:fragment].to_s + percent_encode(c, FRAGMENT_PERCENT_ENCODE_SET)
    end

    def windows_drive_letter?(str)
      WINDOWS_DRIVE_LETTER.match?(str)
    end

    def starts_with_windows_drive_letter?(str)
      STARTS_WITH_wINDOWS_DRIVE_LETTER.match?(str)
    end

    def normalized_windows_drive_letter?(str)
      NORMALIZED_WINDOWS_DRIVE_LETTER.match?(str)
    end

    def special_url?
      SPECIAL_SCHEME.keys.include?(@parse_result[:scheme])
    end

    def single_dot_path_segments?(c)
      SINGLE_DOT_PATH_SEGMENTS.include?(c)
    end

    def double_dot_path_segments?(c)
      DOUBLE_DOT_PATH_SEGMENTS.include?(c)
    end

    def shorten_url_path
      return if @parse_result[:path]&.empty?

      return true if @parse_result[:scheme] == "file" && @parse_result[:path]&.length == 1 && normalized_windows_drive_letter?(@parse_result[:path])
      @parse_result[:path]&.chomp!
    end

    def decrease_pos(c)
      if c.nil?
        @force_continue = true
      else
        @scanner.pos -= c.bytesize
      end
    end
  end
end

URI.send(:remove_const, :DEFAULT_PARSER) if defined?(URI::DEFAULT_PARSER)
URI::DEFAULT_PARSER = URI::WhatwgParser.new
URI.parser = URI::DEFAULT_PARSER
