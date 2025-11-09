require "uri/generic"

module URI
  class WhatwgParser
    module Generic
      def merge(oth)
        URI::DEFAULT_PARSER.join(self.to_s, oth.to_s)
      end
      alias + merge
    end
  end
end

URI::Generic.prepend(URI::WhatwgParser::Generic)
