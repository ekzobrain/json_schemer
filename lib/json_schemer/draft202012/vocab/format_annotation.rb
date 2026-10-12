# frozen_string_literal: true
module JSONSchemer
  module Draft202012
    module Vocab
      module FormatAnnotation
        class Format < Keyword
          def error(formatted_instance_location:, **)
            "value at #{formatted_instance_location} does not match format: #{value}"
          end

          def parse
            root.format && root.fetch_format(value, false)
          end

          def validate(instance, instance_location, keyword_location, context)
            valid = parsed == false || parsed.call(instance, value)
            leaf_result(context, instance, instance_location, keyword_location, valid, :annotation => value)
          end

        end
      end
    end
  end
end
