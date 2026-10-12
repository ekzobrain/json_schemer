# frozen_string_literal: true
module JSONSchemer
  module OpenAPI32
    module Vocab
      module Base
        # https://spec.openapis.org/oas/v3.2.0#discriminator-object
        class Discriminator < OpenAPI31::Vocab::Base::Discriminator
          # "discriminator MUST NOT change the validation outcome of the schema"
          DEFAULT_MODE = 'hint'

          def default_mapping_subschema
            return @default_mapping_subschema if defined?(@default_mapping_subschema)
            default_mapping = value['defaultMapping']
            @default_mapping_subschema = default_mapping && mapped_subschema(default_mapping)
          end

        private

          # Without a mapped value for the discriminating property (missing or without an explicit or implicit mapping),
          # the `defaultMapping` schema is the discriminated one.
          def discriminated_subschema(instance)
            property_name = value['propertyName']
            subschema = subschemas_by_property_value[instance.fetch(property_name)] if property_name && instance.key?(property_name)
            subschema || default_mapping_subschema
          end

          # Schema name (preferred) or URI reference, like `mapping` values: one of the `anyOf`/`oneOf` subschemas when
          # adjacent to them, otherwise resolved like an implicit mapping (`allOf` parent).
          def mapped_subschema(schema_name_or_ref)
            return resolve_schema_name_or_ref(schema_name_or_ref) unless schema.parsed.key?('anyOf') || schema.parsed.key?('oneOf')

            subschemas = (schema.parsed['anyOf']&.parsed || []) + (schema.parsed['oneOf']&.parsed || [])
            refs = [schema_name_or_ref]
            refs.unshift("#/components/schemas/#{schema_name_or_ref}") if FIXED_FIELD_REGEX.match?(schema_name_or_ref)
            refs.each do |ref|
              subschema = subschemas.find { |candidate| candidate.parsed['$ref']&.parsed == ref }
              return subschema if subschema
            end
            nil
          end
        end
      end
    end
  end
end
