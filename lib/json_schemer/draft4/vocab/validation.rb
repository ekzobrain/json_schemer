# frozen_string_literal: true
module JSONSchemer
  module Draft4
    module Vocab
      module Validation
        class Type < Draft202012::Vocab::Validation::Type
          def self.valid_integer?(instance)
            instance.is_a?(Integer)
          end
        end

        class ExclusiveMaximum < Keyword
          def error(formatted_instance_location:, **)
            "number at #{formatted_instance_location} is greater than or equal to `maximum`"
          end

          def validate(instance, instance_location, keyword_location, context)
            maximum = schema.parsed.fetch('maximum').parsed
            valid = !instance.is_a?(Numeric) || !value || !maximum || instance < maximum
            leaf_result(context, instance, instance_location, keyword_location, valid)
          end

        end

        class ExclusiveMinimum < Keyword
          def error(formatted_instance_location:, **)
            "number at #{formatted_instance_location} is less than or equal to `minimum`"
          end

          def validate(instance, instance_location, keyword_location, context)
            minimum = schema.parsed.fetch('minimum').parsed
            valid = !instance.is_a?(Numeric) || !value || !minimum || instance > minimum
            leaf_result(context, instance, instance_location, keyword_location, valid)
          end

        end
      end
    end
  end
end
