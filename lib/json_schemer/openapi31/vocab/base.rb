# frozen_string_literal: true
module JSONSchemer
  module OpenAPI31
    module Vocab
      module Base
        class AllOf < Draft202012::Vocab::Applicator::AllOf
          attr_accessor :skip_ref_once

          def validate(instance, instance_location, keyword_location, context)
            nested = []
            parsed.each_with_index do |subschema, index|
              if ref_schema = subschema.parsed['$ref']&.ref_schema
                next if skip_ref_once == ref_schema.absolute_keyword_location
                ref_schema.parsed['discriminator']&.skip_ref_once = schema.absolute_keyword_location
              end
              nested << subschema.validate_instance(instance, instance_location, join_location(keyword_location, Location.index_name(index)), context)
            end
            result(instance, instance_location, keyword_location, nested.all?(&:valid), nested)
          ensure
            self.skip_ref_once = nil
          end

        end

        # `anyOf`/`oneOf` adjacent to `discriminator`: left to `discriminator` when it selects the schema validating the
        # instance (`discriminator_mode: 'select'`), otherwise evaluated as usual, with only the errors of the
        # discriminated subschema when it is invalid (`'hint'`).
        module DiscriminatedApplicator
          def validate(instance, instance_location, keyword_location, context)
            discriminator = schema.parsed['discriminator']
            return super unless discriminator
            return if discriminator.selects_schema?
            discriminator.discriminated_result(super, instance)
          end

          def valid_instance?(instance, context)
            schema.parsed['discriminator']&.selects_schema? ? nil : super
          end
        end

        class AnyOf < Draft202012::Vocab::Applicator::AnyOf
          include DiscriminatedApplicator
        end

        class OneOf < Draft202012::Vocab::Applicator::OneOf
          include DiscriminatedApplicator
        end

        class Discriminator < Keyword
          # https://spec.openapis.org/oas/v3.1.0#components-object
          FIXED_FIELD_REGEX = /\A[a-zA-Z0-9\.\-_]+$\z/
          # OpenAPI 3.0 and 3.1.0 allow the discriminator to "shortcut validation and selection of the matching schema",
          # OpenAPI 3.1.1+ and 3.2 say it "MUST NOT change the validation outcome of the schema". `JSONSchemer.openapi`
          # sets `discriminator_mode` by the document version.
          DEFAULT_MODE = 'select'

          attr_accessor :skip_ref_once

          # Whether the discriminated schema validates the instance instead of adjacent `anyOf`/`oneOf` (and a parent
          # schema validates the discriminated child schema referencing it in `allOf`): `discriminator_mode: 'select'`.
          # With `'hint'` the discriminator doesn't change the validation outcome and only selects the subschema whose
          # errors are reported.
          def selects_schema?
            return @selects_schema if defined?(@selects_schema)
            @selects_schema = (schema.configuration.discriminator_mode || self.class::DEFAULT_MODE) == 'select'
          end

          # Result of adjacent `anyOf`/`oneOf` with only the result of the discriminated subschema when it is invalid
          # (`'hint'` mode).
          def discriminated_result(keyword_result, instance)
            return keyword_result if keyword_result.valid || !keyword_result.nested || !instance.is_a?(Hash)
            subschema = discriminated_subschema(instance)
            subschema_result = keyword_result.nested.find { |nested_result| nested_result.source.equal?(subschema) } if subschema
            keyword_result.nested = [subschema_result] if subschema_result && !subschema_result.valid
            keyword_result
          end

          def error(formatted_instance_location:, **)
            "value at #{formatted_instance_location} does not match `discriminator` schema"
          end

          def mapping
            @mapping ||= value['mapping'] || {}
          end

          def subschemas_by_property_value
            @subschemas_by_property_value ||= if schema.parsed.key?('anyOf') || schema.parsed.key?('oneOf')
              subschemas = schema.parsed['anyOf']&.parsed || []
              subschemas += schema.parsed['oneOf']&.parsed || []

              subschemas_by_ref = {}
              subschemas_by_schema_name = {}

              subschemas.each do |subschema|
                # inline subschemas aren't considered for implicit or explicit mappings
                next unless subschema.parsed.key?('$ref')

                subschema_ref = subschema.parsed.fetch('$ref').parsed
                subschemas_by_ref[subschema_ref] = subschema

                if subschema_ref.start_with?('#/components/schemas/')
                  schema_name = subschema_ref.delete_prefix('#/components/schemas/')
                  subschemas_by_schema_name[schema_name] = subschema if FIXED_FIELD_REGEX.match?(schema_name)
                end
              end

              explicit_mapping = mapping.transform_values do |schema_name_or_ref|
                subschemas_by_schema_name.fetch(schema_name_or_ref) { subschemas_by_ref.fetch(schema_name_or_ref) }
              end

              implicit_mapping = subschemas_by_schema_name.reject do |_schema_name, subschema|
                explicit_mapping.value?(subschema)
              end

              implicit_mapping.merge(explicit_mapping)
            else
              Hash.new do |hash, property_value|
                hash[property_value] = resolve_schema_name_or_ref(mapping.fetch(property_value, property_value))
              end
            end
          end

          def validate(instance, instance_location, keyword_location, context)
            return unless selects_schema?
            return result(instance, instance_location, keyword_location, false) unless instance.is_a?(Hash)

            subschema = discriminated_subschema(instance)

            return result(instance, instance_location, keyword_location, false) unless subschema

            return if skip_ref_once == subschema.absolute_keyword_location
            subschema.parsed['allOf']&.skip_ref_once = schema.absolute_keyword_location

            subschema_result = subschema.validate_instance(instance, instance_location, keyword_location, context)

            result(instance, instance_location, keyword_location, subschema_result.valid, subschema_result.nested)
          ensure
            self.skip_ref_once = nil
          end

          def valid_instance?(_instance, _context)
            selects_schema? ? nil : true
          end

        private

          # Schema of a component (`#/components/schemas/<name>`) or else of a URI reference, or nil.
          def resolve_schema_name_or_ref(schema_name_or_ref)
            subschema = nil

            if FIXED_FIELD_REGEX.match?(schema_name_or_ref)
              subschema = begin
                schema.ref("#/components/schemas/#{schema_name_or_ref}")
              rescue InvalidRefPointer
                nil
              end
            end

            subschema || begin
              schema.ref(schema_name_or_ref)
            rescue InvalidRefResolution, UnknownRef
              nil
            end
          end

          # Subschema selected by the discriminating property of the instance (a Hash), or nil.
          def discriminated_subschema(instance)
            property_name = value.fetch('propertyName')
            subschemas_by_property_value[instance.fetch(property_name)] if instance.key?(property_name)
          end
        end
      end
    end
  end
end
