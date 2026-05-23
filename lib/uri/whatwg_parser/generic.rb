require "uri/generic"

module URI
  class WhatwgParser
    module Generic
      def initialize(scheme,
                     userinfo, host, port, registry,
                     path, opaque,
                     query,
                     fragment,
                     parser = DEFAULT_PARSER,
                     arg_check = false)

        return super unless URI::DEFAULT_PARSER.is_a?(URI::WhatwgParser)

        @scheme = nil
        @user = nil
        @password = nil
        @host = nil
        @port = nil
        @path = nil
        @raw_path = nil
        @query = nil
        @opaque = nil
        @fragment = nil
        @parser = parser == DEFAULT_PARSER ? nil : parser

        self.set_scheme(scheme)
        self.set_host(host)
        self.set_port(port)
        self.set_userinfo(userinfo)
        self.set_path(path)
        self.query = query
        self.set_opaque(opaque)
        @fragment = fragment
        @raw_path = parser&.path

        self.set_path("") if !@path && !@opaque
        DEFAULT_PARSER.parse(to_s) if arg_check

        @scheme&.freeze
        self.set_port(self.default_port) if self.default_port && !@port
      end

      def merge(oth)
        return super unless parsed_by_whatwg_parser?

        URI::DEFAULT_PARSER.join(self.to_s, oth.to_s)
      end
      alias + merge

      def scheme=(v)
        return super unless parsed_by_whatwg_parser?
        return if v.nil? || v.empty?

        parse_result = URI::DEFAULT_PARSER.split("#{v}:", url: self, state_override: :scheme_start_state)
        set_scheme(parse_result[0])
        set_port(parse_result[3])
      end

      def user=(v)
        return super unless parsed_by_whatwg_parser?
        return v unless v

        if host.nil? || host.empty? || scheme == "file"
          raise InvalidURIError, "cannot set user when host is nil or file schme"
        end
        set_user(URI::DEFAULT_PARSER.utf8_percent_encode_string(v, URI::WhatwgParser::USERINFO_PERCENT_ENCODE_SET))
      end

      def password=(v)
        return super unless parsed_by_whatwg_parser?
        return v unless v

        if host.nil? || host.empty? || scheme == "file"
          raise InvalidURIError, "cannot set password when host is nil or file schme"
        end
        set_password(URI::DEFAULT_PARSER.utf8_percent_encode_string(v, URI::WhatwgParser::USERINFO_PERCENT_ENCODE_SET))
      end

      def host=(v)
        return super unless parsed_by_whatwg_parser?
        return if v.nil?

        if @opaque
          raise InvalidURIError, "cannot set host with opaque"
        end

        parse_result = URI::DEFAULT_PARSER.split(v.to_s, url: self, state_override: :host_state)
        set_host(parse_result[2])
        set_port(parse_result[3])
      end

      def port=(v)
        return super unless parsed_by_whatwg_parser?
        return if v.nil?

        if v.to_s.empty?
          set_port(nil)
          return
        end

        if host.nil? || host.empty? || scheme == "file"
          raise InvalidURIError, "cannot set port when host is nil or scheme is file"
        end

        parse_result = URI::DEFAULT_PARSER.split("#{v}:", url: self, state_override: :port_state)
        set_port(parse_result[3])
      end

      def path=(v)
        return super unless parsed_by_whatwg_parser?
        return if v.nil?

        if @opaque
          raise InvalidURIError, "path conflicts with opaque"
        end

        parse_result = URI::DEFAULT_PARSER.split(v.to_s, url: self, state_override: :path_start_state)
        @raw_path = parser.path
        set_path(parse_result[5])
      end

      def query=(v)
        return super unless parsed_by_whatwg_parser?

        if v.nil? || v.empty?
          @query = nil
          return
        end

        v = v.start_with?("?") ? v[1..-1] : v
        @query = +""

        parse_result = URI::DEFAULT_PARSER.split(v, url: self, state_override: :query_state)
        @query = parse_result[7].to_s
      end

      def fragment=(v)
        return super unless parsed_by_whatwg_parser?

        if v.nil? || v.empty?
          @fragment = nil
          return
        end

        v = v.start_with?("#") ? v[1..-1] : v
        @fragment = +""

        parse_result = URI::DEFAULT_PARSER.split(v, url: self, state_override: :fragment_state)
        @fragment = parse_result[8].to_s
      end

      def userinfo=(userinfo)
        return super unless parsed_by_whatwg_parser?

        user, password = split_userinfo(userinfo)
        self.user = user
        self.password = password
      end

      def check_opaque(v)
        return super unless parsed_by_whatwg_parser?

        return v unless v

        if @host || @port || @user
          raise InvalidURIError, "cannot set opaque with host, port, or userinfo"
        end

        self.set_opaque(v)
        DEFAULT_PARSER.parse(to_s)
        true
      end

      def to_s
        return super unless parsed_by_whatwg_parser?

        str = "".dup
        if @scheme
          str << @scheme
          str << ":"
        end

        if @host || %w[file postgres].include?(@scheme)
          str << "//"
        end
        if self.userinfo
          str << self.userinfo
          str << "@"
        end
        if @host
          str << @host
        end
        if @port && @port != self.default_port
          str << ":"
          str << @port.to_s
        end
        if @host.nil? && @opaque.nil? && @raw_path && @raw_path.length > 1 && @raw_path[0] == ""
          str << "/."
        end
        str << @path if @path
        str << @opaque if @opaque
        if @query
          str << "?"
          str << @query
        end

        if @fragment
          str << "#"
          str << @fragment
        end
        str
      end

      private

      def parsed_by_whatwg_parser?
        self.parser.is_a?(URI::WhatwgParser)
      end
    end
  end
end

URI::Generic.prepend(URI::WhatwgParser::Generic)
