require "uri/generic"

module URI
  class WhatwgParser
    module Generic
      def merge(oth)
        URI::DEFAULT_PARSER.join(self.to_s, oth.to_s)
      end
      alias + merge

      def check_scheme(v)
        parser = URI::WhatwgParser.new
        v.split("").each do |c|
          parser.send(:scheme_state, c)
        end

        if v && parser.instance_variable_get(:@buffer) != v
          raise InvalidComponentError,
            "bad component(expected scheme component): #{v}"
        end

        true
      end

      def check_user(v)
        if @opaque
          raise InvalidURIError,
            "cannot set user with opaque"
        end

        return v unless v

        parser = URI::WhatwgParser.new
        v.split("").each do |c|
          parser.send(:authority_state, c)
        end

        if v && parser.instance_variable_get(:@buffer) != v
          raise InvalidComponentError,
            "bad component(expected userinfo component or user component): #{v}"
        end

        true
      end

      def check_password(v, user = @user)
        if @opaque
          raise InvalidURIError,
            "cannot set password with opaque"
        end
        return v unless v

        if !user
          raise InvalidURIError,
            "password component depends user component"
        end

        parser = URI::WhatwgParser.new
        v.split("").each do |c|
          parser.send(:authority_state, c)
        end

        if v && parser.instance_variable_get(:@buffer) != v
          raise InvalidComponentError,
            "bad password component"
        end

        true
      end

      def check_host(v)
      end

      def check_port(v)
      end

      def check_path(v)
      end

      def check_opaque(v)
      end
    end
  end
end

URI::Generic.prepend(URI::WhatwgParser::Generic)
