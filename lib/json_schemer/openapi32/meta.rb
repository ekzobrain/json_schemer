# frozen_string_literal: true
module JSONSchemer
  module OpenAPI32
    # https://spec.openapis.org/oas/3.2/dialect/2025-09-17 (the default of `jsonSchemaDialect` in the OpenAPI 3.2
    # document schema; the 3.2.0 specification text still names https://spec.openapis.org/oas/3.1/dialect/base, which is
    # supported too)
    BASE_URI = URI('https://spec.openapis.org/oas/3.2/dialect/2025-09-17')
    # https://spec.openapis.org/oas/v3.2.0#data-type-format (same as 3.1)
    FORMATS = OpenAPI31::FORMATS
    SCHEMA = {
      '$id' => 'https://spec.openapis.org/oas/3.2/dialect/2025-09-17',
      '$schema' => 'https://json-schema.org/draft/2020-12/schema',
      'title' => 'OpenAPI 3.2 Schema Object Dialect',
      'description' => 'A JSON Schema dialect describing schemas found in OpenAPI v3.2.x Descriptions',
      '$dynamicAnchor' => 'meta',
      '$vocabulary' => {
        'https://json-schema.org/draft/2020-12/vocab/applicator' => true,
        'https://json-schema.org/draft/2020-12/vocab/content' => true,
        'https://json-schema.org/draft/2020-12/vocab/core' => true,
        'https://json-schema.org/draft/2020-12/vocab/format-annotation' => true,
        'https://json-schema.org/draft/2020-12/vocab/meta-data' => true,
        'https://json-schema.org/draft/2020-12/vocab/unevaluated' => true,
        'https://json-schema.org/draft/2020-12/vocab/validation' => true,
        'https://spec.openapis.org/oas/3.2/vocab/base' => false
      },
      'allOf' => [
        {
          '$ref' => 'https://json-schema.org/draft/2020-12/schema'
        },
        {
          '$ref' => 'https://spec.openapis.org/oas/3.2/meta/2025-09-17'
        }
      ]
    }

    module Meta
      BASE = {
        '$id' => 'https://spec.openapis.org/oas/3.2/meta/2025-09-17',
        '$schema' => 'https://json-schema.org/draft/2020-12/schema',
        'title' => 'OAS Base Vocabulary',
        'description' => 'A JSON Schema Vocabulary used in the OpenAPI JSON Schema Dialect',
        '$dynamicAnchor' => 'meta',
        '$vocabulary' => {
          'https://spec.openapis.org/oas/3.2/vocab/base' => true
        },
        'type' => [
          'object',
          'boolean'
        ],
        'properties' => {
          'discriminator' => {
            '$ref' => '#/$defs/discriminator'
          },
          'example' => {
            'deprecated' => true
          },
          'externalDocs' => {
            '$ref' => '#/$defs/external-docs'
          },
          'xml' => {
            '$ref' => '#/$defs/xml'
          }
        },
        '$defs' => {
          'discriminator' => {
            '$ref' => '#/$defs/extensible',
            'properties' => {
              'mapping' => {
                'additionalProperties' => {
                  'type' => 'string'
                },
                'type' => 'object'
              },
              'defaultMapping' => {
                'type' => 'string'
              },
              'propertyName' => {
                'type' => 'string'
              }
            },
            'type' => 'object',
            'unevaluatedProperties' => false
          },
          'extensible' => {
            'patternProperties' => {
              '^x-' => true
            }
          },
          'external-docs' => {
            '$ref' => '#/$defs/extensible',
            'properties' => {
              'description' => {
                'type' => 'string'
              },
              'url' => {
                'format' => 'uri-reference',
                'type' => 'string'
              }
            },
            'required' => [
              'url'
            ],
            'type' => 'object',
            'unevaluatedProperties' => false
          },
          'xml' => {
            '$ref' => '#/$defs/extensible',
            'properties' => {
              'nodeType' => {
                'type' => 'string',
                'enum' => [
                  'element',
                  'attribute',
                  'text',
                  'cdata',
                  'none'
                ]
              },
              'name' => {
                'type' => 'string'
              },
              'namespace' => {
                'format' => 'iri',
                'type' => 'string'
              },
              'prefix' => {
                'type' => 'string'
              },
              'attribute' => {
                'type' => 'boolean',
                'deprecated' => true
              },
              'wrapped' => {
                'type' => 'boolean',
                'deprecated' => true
              }
            },
            'type' => 'object',
            'dependentSchemas' => {
              'nodeType' => {
                'properties' => {
                  'attribute' => false,
                  'wrapped' => false
                }
              }
            },
            'unevaluatedProperties' => false
          }
        }
      }

      SCHEMAS = Draft202012::Meta::SCHEMAS.merge(
        Draft202012::BASE_URI => Draft202012::SCHEMA,
        URI('https://spec.openapis.org/oas/3.2/meta/2025-09-17') => BASE
      )
    end
  end
end
