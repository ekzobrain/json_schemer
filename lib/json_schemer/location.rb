# frozen_string_literal: true
module JSONSchemer
  module Location
    JSON_POINTER_TOKEN_ESCAPE_CHARS = { '~' => '~0', '/' => '~1' }
    JSON_POINTER_TOKEN_ESCAPE_REGEX = Regexp.union(JSON_POINTER_TOKEN_ESCAPE_CHARS.keys)
    # array indexes are converted to location names for every validated item
    INDEX_NAMES = Array.new(1024) { |index| index.to_s.freeze }.freeze

    class << self
      def root
        {}
      end

      def index_name(index)
        INDEX_NAMES[index] || index.to_s
      end

      def join(location, name)
        location[name] ||= { :name => name, :parent => location }
      end

      def resolve(location)
        location[:resolve] ||= location[:parent] ? "#{resolve(location[:parent])}/#{escape_json_pointer_token(location[:name])}" : ''
      end

      def escape_json_pointer_token(token)
        JSON_POINTER_TOKEN_ESCAPE_REGEX.match?(token) ? token.gsub(JSON_POINTER_TOKEN_ESCAPE_REGEX, JSON_POINTER_TOKEN_ESCAPE_CHARS) : token
      end
    end
  end
end
