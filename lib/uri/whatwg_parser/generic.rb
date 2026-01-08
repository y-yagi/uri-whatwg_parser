require "uri/generic"

module URI
  class WhatwgParser
    module Generic
      def initialize(scheme,
                     userinfo, host, port, registry,
                     path, opaque,
                     query,
                     fragment,
                     parser = PARSER,
                     arg_check = false)

        return super unless URI::PARSER.is_a?(URI::WhatwgParser)
        return super if registry

        @scheme = nil
        @user = nil
        @password = nil
        @host = nil
        @port = nil
        @path = nil
        @query = nil
        @opaque = nil
        @fragment = nil
        @parser = parser == PARSER ? nil : parser

        self.set_scheme(scheme)
        self.set_host(host)
        self.set_port(port)
        self.set_userinfo(userinfo)
        self.set_path(path)
        self.query = query
        self.set_opaque(opaque)
        self.fragment=(fragment)

        self.set_path("") if !@path && !@opaque
        PARSER.parse(to_s) if arg_check

        @scheme&.freeze
        self.set_port(self.default_port) if self.default_port && !@port
      end

      def merge(oth)
        URI::PARSER.join(self.to_s, oth.to_s)
      end
      alias + merge

      def scheme=(v)
        return super unless URI::PARSER.is_a?(URI::WhatwgParser)
        return if v.nil? || v.empty?

        parse_result = URI::PARSER.split("#{v}:", url: self, state_override: :scheme_start_state)
        set_scheme(parse_result[0])
        set_port(parse_result[3])
      end

      def user=(v)
        return super unless URI::PARSER.is_a?(URI::WhatwgParser)
        return v unless v

        if host.nil? || host.empty? || scheme == "file"
          raise InvalidURIError, "cannot set user when host is nil or file schme"
        end
        set_user(URI::PARSER.encode_userinfo(v))
      end

      def password=(v)
        return super unless URI::PARSER.is_a?(URI::WhatwgParser)
        return v unless v

        if host.nil? || host.empty? || scheme == "file"
          raise InvalidURIError, "cannot set password when host is nil or file schme"
        end
        set_password(URI::PARSER.encode_userinfo(v))
      end

      def host=(v)
        return super unless URI::PARSER.is_a?(URI::WhatwgParser)
        return if v.nil?

        if @opaque
          raise InvalidURIError, "cannot set host with registry or opaque"
        end

        parse_result = URI::PARSER.split(v.to_s, url: self, state_override: :host_state)
        set_host(parse_result[2])
        set_port(parse_result[3])
      end

      def port=(v)
        return super unless URI::PARSER.is_a?(URI::WhatwgParser)
        return if v.nil?

        if v.to_s.empty?
          set_port(nil)
          return
        end

        if host.nil? || host.empty? || scheme == "file"
          raise InvalidURIError, "cannot set port when host is nil or scheme is file"
        end

        parse_result = URI::PARSER.split("#{v}:", url: self, state_override: :port_state)
        set_port(parse_result[3])
      end

      def path=(v)
        return super unless URI::PARSER.is_a?(URI::WhatwgParser)
        return if v.nil?

        if @opaque
          raise InvalidURIError, "path conflicts with opaque"
        end

        parse_result = URI::PARSER.split(v.to_s, url: self, state_override: :path_start_state)
        set_path(parse_result[5])
      end

      def userinfo=(userinfo)
        return super unless URI::PARSER.is_a?(URI::WhatwgParser)

        user, password = split_userinfo(userinfo)
        self.user = user
        self.password = password
      end

      def check_opaque(v)
        return super unless URI::PARSER.is_a?(URI::WhatwgParser)
        return v unless v

        if @host || @port || @user || @path
          raise InvalidURIError, "cannot set opaque with host, port, userinfo or path"
        end

        self.set_opaque(v)
        PARSER.parse(to_s)
        true
      end
    end
  end
end

URI::Generic.prepend(URI::WhatwgParser::Generic)
