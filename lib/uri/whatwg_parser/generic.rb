require "uri/generic"

module URI
  class WhatwgParser
    module Generic
      def merge(oth)
        URI::DEFAULT_PARSER.join(self.to_s, oth.to_s)
      end
      alias + merge

      def check_scheme(v)
        self.set_scheme(v)
        DEFAULT_PARSER.parse(to_s)
        true
      end

      def check_user(v)
        if @opaque
          raise InvalidURIError, "cannot set user with opaque"
        end

        return v unless v

        self.set_user(v)
        DEFAULT_PARSER.parse(to_s)
        true
      end

      def check_password(v, user = @user)
        if @opaque
          raise InvalidURIError, "cannot set password with opaque"
        end
        return v unless v

        if !user
          raise InvalidURIError, "password component depends user component"
        end

        self.set_password(v)
        DEFAULT_PARSER.parse(to_s)
        true
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

      def check_port(v)
        return v unless v

        if @opaque
          raise InvalidURIError, "cannot set port with registry or opaque"
        end

        self.set_port(v)
        DEFAULT_PARSER.parse(to_s)
        true
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
