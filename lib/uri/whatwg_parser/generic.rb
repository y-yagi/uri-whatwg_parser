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
        @scheme = nil
        @user = nil
        @password = nil
        @host = nil
        @port = nil
        @path = nil
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
        self.fragment=(fragment)

        self.set_path("") if !@path && !@opaque
        DEFAULT_PARSER.parse(to_s) if arg_check

        if registry
          raise InvalidURIError,
            "the scheme #{@scheme} does not accept registry part: #{registry} (or bad hostname?)"
        end

        @scheme&.freeze
        self.set_port(self.default_port) if self.default_port && !@port
      end


      def merge(oth)
        URI::DEFAULT_PARSER.join(self.to_s, oth.to_s)
      end
      alias + merge

      def scheme=(v)
        URI::DEFAULT_PARSER.parse("#{v}:", url: self, state_override: :scheme_start_state)
        set_scheme(v)
      end

      def user=(v)
        if host.nil? || scheme == "file"
          raise InvalidURIError, "cannot set user when host is nil or file schme"
        end
        set_user(URI::DEFAULT_PARSER.encode_userinfo(v))
      end

      def password=(v)
        if host.nil? || scheme == "file"
          raise InvalidURIError, "cannot set password when host is nil or file schme"
        end
        set_password(URI::DEFAULT_PARSER.encode_userinfo(v))
      end

      def check_host(v)
        return v unless v

        if @opaque
          raise InvalidURIError, "cannot set host with registry or opaque"
        end

        self.set_host(v)
        DEFAULT_PARSER.parse(to_s)
        true
      end

      def port=(v)
        if host.nil? || scheme == "file"
          raise InvalidURIError, "cannot set port when host is nil or file schme"
        end

        URI::DEFAULT_PARSER.parse(v.to_s, url: self, state_override: :port_state) unless v.to_s.empty?
        set_port(v)
      end

      def check_path(v)
        return v unless v

        if @opaque
          raise InvalidURIError, "path conflicts with opaque"
        end

        self.set_path(v)
        DEFAULT_PARSER.parse(to_s)
        true
      end

      def check_opaque(v)
        return v unless v

        if @host || @port || @user || @path
          raise InvalidURIError, "cannot set opaque with host, port, userinfo or path"
        end

        self.set_opaque(v)
        DEFAULT_PARSER.parse(to_s)
        true
      end
    end
  end
end

URI::Generic.prepend(URI::WhatwgParser::Generic)
