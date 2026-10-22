require 'test_helper'
require 'yaml'

class OpenAPIDeepValidationTest < Minitest::Test
  FIXTURES = File.expand_path('fixtures/openapi', __dir__)
  INFO = { 'title' => 'test', 'version' => '1' }.freeze

  # documents of a directory by `file:///` URI, like a resolver over a set of files would see them
  def fixture_documents(directory)
    Dir.chdir(directory) { Dir['**/*.{yaml,json}'] }.to_h do |file|
      content = File.read(File.join(directory, file))
      ["file:///#{file}", file.end_with?('.json') ? JSON.parse(content) : YAML.safe_load(content)]
    end
  end

  def openapi(documents, entry = 'file:///openapi.yaml', calls: nil)
    resolver = proc do |uri|
      calls << uri.to_s if calls
      documents[uri.to_s]
    end
    JSONSchemer.openapi(documents.fetch(entry), :base_uri => URI(entry), :ref_resolver => resolver)
  end

  def deep_errors(documents, entry = 'file:///openapi.yaml', **options)
    openapi(documents, entry).validate(:deep => true, :output_format => 'basic', **options).fetch('errors')
  end

  def error_locations(errors)
    errors.map { |error| error.fetch('absoluteInstanceLocation') }.uniq
  end

  def test_fixtures
    calls = []
    documents = fixture_documents(File.join(FIXTURES, 'split'))
    split = openapi(documents, :calls => calls)
    assert(split.valid?)
    assert(split.valid?(:deep => true))
    assert_equal([], split.validate(:deep => true).to_a)
    assert_equal({ 'valid' => true, 'errors' => [] }, split.validate(:deep => true, :output_format => 'basic'))
    assert_equal(documents.keys.sort - ['file:///openapi.yaml'], calls.uniq.sort)

    documents = fixture_documents(FIXTURES)
    ['file:///petstore-xml.yaml', 'file:///petstore.json', 'file:///as-asp.yaml'].each do |entry|
      assert(openapi(documents, entry).valid?(:deep => true), entry)
    end
  end

  def mutated_split
    documents = fixture_documents(File.join(FIXTURES, 'split'))
    yield documents
    documents
  end

  def test_split_errors
    errors = deep_errors(mutated_split { |documents| documents['file:///common.yaml']['components']['schemas']['Error']['properties']['code']['type'] = 'intger' })
    assert_equal(['file:///common.yaml#/components/schemas/Error/properties/code', 'file:///common.yaml#/components/schemas/Error/properties/code/type'], error_locations(errors))
    assert_equal(['Schema'], errors.map { |error| error.fetch('expected') }.uniq)
    assert(errors.all? { |error| error.fetch('keywordLocation').start_with?('/definitions/Schema/') })

    errors = deep_errors(mutated_split { |documents| documents['file:///common.yaml']['components']['parameters']['Verbose']['in'] = 'body' })
    assert_includes(error_locations(errors), 'file:///common.yaml#/components/parameters/Verbose/in')
    assert_equal(['Parameter'], errors.map { |error| error.fetch('expected') }.uniq)

    errors = deep_errors(mutated_split { |documents| documents['file:///common.yaml']['components']['responses']['NotFound'].delete('description') })
    assert_equal(['object at `/components/responses/NotFound` is missing required properties: description'], errors.map { |error| error.fetch('error') })
    assert_equal(['file:///common.yaml#/components/responses/NotFound'], error_locations(errors))
    assert_equal(['Response'], errors.map { |error| error.fetch('expected') })

    errors = deep_errors(mutated_split { |documents| documents['file:///paths/pets.yaml']['post'].delete('responses') })
    assert_equal(['object at `/post` is missing required properties: responses'], errors.map { |error| error.fetch('error') })
    assert_equal(['file:///paths/pets.yaml#/post'], error_locations(errors))

    errors = deep_errors(mutated_split { |documents| documents.delete('file:///schemas/category.json') })
    assert_equal(["value at `/properties/category/$ref` references `category.json`, which can't be retrieved: not found"], errors.map { |error| error.fetch('error') })
    assert_equal(['file:///schemas/pet.yaml#/properties/category/$ref'], error_locations(errors))
    assert_equal([{ 'value' => 'category.json', 'uri' => 'file:///schemas/category.json' }], errors.map { |error| error.fetch('ref') })

    errors = deep_errors(mutated_split { |documents| documents['file:///openapi.yaml']['paths']['/pets/{id}']['get']['responses']['404']['$ref'] = 'common.yaml#/components/responses/NotFnd' })
    assert_equal(["value at `/paths/~1pets~1{id}/get/responses/404/$ref` references `common.yaml#/components/responses/NotFnd`, but pointer `/components/responses/NotFnd` doesn't exist in `file:///common.yaml`"], errors.map { |error| error.fetch('error') })
    assert_equal(['file:///openapi.yaml#/paths/~1pets~1%7Bid%7D/get/responses/404/$ref'], error_locations(errors))
    assert_equal(['Response'], errors.map { |error| error.fetch('expected') })

    errors = deep_errors(mutated_split { |documents| documents['file:///schemas/pet.yaml']['properties']['category']['$ref'] = '../../category.json' })
    assert_equal([{ 'value' => '../../category.json', 'uri' => 'file:///category.json' }], errors.map { |error| error.fetch('ref') })

    # root-only validation lets them all through
    documents = mutated_split { |documents| documents.delete('file:///schemas/category.json') }
    assert(openapi(documents).valid?)
    refute(openapi(documents).valid?(:deep => true))
  end

  def test_output_formats
    documents = mutated_split { |documents| documents['file:///common.yaml']['components']['responses']['NotFound'].delete('description') }
    assert_equal({ 'valid' => false }, openapi(documents).validate(:deep => true, :output_format => 'flag'))
    classic = openapi(documents).validate(:deep => true)
    assert_equal(['file:///common.yaml#/components/responses/NotFound'], classic.map { |error| error.fetch('data_uri') })
    assert_equal(['/components/responses/NotFound'], classic.map { |error| error.fetch('data_pointer') })
    assert_equal(['Response'], classic.map { |error| error.fetch('expected') })
    assert_raises(JSONSchemer::UnknownOutputFormat) { openapi(documents).validate(:deep => true, :output_format => 'detailed') }
  end

  def test_invalid_root
    documents = { 'file:///openapi.yaml' => { 'openapi' => '3.0.3', 'info' => {}, 'paths' => { '/a' => { '$ref' => 'missing.yaml' } } } }
    errors = deep_errors(documents)
    # the root's errors, and its references are followed all the same
    assert_includes(error_locations(errors), 'file:///openapi.yaml#/info')
    assert_includes(error_locations(errors), 'file:///openapi.yaml#/paths/~1a/$ref')
  end

  def test_reference_errors
    documents = {
      'file:///openapi.yaml' => {
        'openapi' => '3.1.0',
        'info' => INFO,
        'webhooks' => {
          'a' => { '$ref' => 'paths.yaml#a' },
          'b' => { '$ref' => 'paths.yaml#/b' }
        }
      },
      'file:///paths.yaml' => { 'b' => 'not a path item' }
    }
    errors = deep_errors(documents)
    assert_equal(['file:///openapi.yaml#/webhooks/a/$ref', 'file:///paths.yaml#/b'], error_locations(errors))
    assert_equal("value at `/webhooks/a/$ref` references `paths.yaml#a`, whose fragment isn't a JSON pointer", errors.first.fetch('error'))
    assert_equal(['PathItem'], errors.map { |error| error.fetch('expected') }.uniq)

    # invalid for the document schema too (`uri-reference`)
    documents['file:///openapi.yaml']['webhooks'] = { 'a' => { '$ref' => 'http://[bad' } }
    errors = deep_errors(documents).select { |error| error.key?('ref') }
    assert_equal(['file:///openapi.yaml#/webhooks/a/$ref'], error_locations(errors))
    assert_match(/\Avalue at `\/webhooks\/a\/\$ref` has an invalid reference `http:\/\/\[bad`: /, errors.first.fetch('error'))
  end

  def test_openapi_31
    documents = {
      'file:///openapi.yaml' => {
        'openapi' => '3.1.0',
        'info' => INFO,
        'webhooks' => { 'created' => { '$ref' => 'hooks.yaml#/created' } },
        'components' => {
          'pathItems' => { 'shared' => { '$ref' => 'hooks.yaml#/created' } },
          'schemas' => {
            # an identifier declared in another document
            'Pet' => { '$ref' => 'https://example.com/schemas/pet' },
            'Kind' => { '$ref' => 'https://example.com/schemas/pet#kind' },
            'Draft7' => { '$ref' => 'schemas/draft7.json' },
            'Animal' => {
              'oneOf' => [{ '$ref' => '#/components/schemas/Pet' }],
              'discriminator' => { 'propertyName' => 'kind', 'mapping' => { 'pet' => 'Pet', 'other' => 'schemas/draft7.json' } }
            }
          }
        }
      },
      'file:///hooks.yaml' => {
        'created' => {
          'post' => {
            'requestBody' => { 'content' => { 'application/json' => { 'schema' => { '$ref' => 'schemas/common.yaml#/$defs/Event' } } } },
            'responses' => { '200' => { 'description' => 'OK' } }
          }
        }
      },
      'file:///schemas/common.yaml' => {
        '$defs' => {
          'Event' => { 'type' => 'object', 'properties' => { 'pet' => { '$ref' => 'https://example.com/schemas/pet' } } },
          'Pet' => {
            '$id' => 'https://example.com/schemas/pet',
            'type' => 'object',
            'properties' => { 'kind' => { '$anchor' => 'kind', 'type' => 'string' }, 'self' => { '$dynamicRef' => '#node' } },
            '$dynamicAnchor' => 'node'
          }
        }
      },
      'file:///schemas/draft7.json' => { '$schema' => 'http://json-schema.org/draft-07/schema#', 'type' => 'object' }
    }
    assert_equal([], deep_errors(documents))

    documents['file:///schemas/common.yaml']['$defs']['Pet']['properties']['kind']['type'] = 'strng'
    documents['file:///schemas/draft7.json']['exclusiveMaximum'] = true
    documents['file:///hooks.yaml']['created']['post']['requestBody']['required'] = 'yes'
    errors = deep_errors(documents)
    assert_equal(
      [
        'file:///hooks.yaml#/created/post/requestBody/required',
        'file:///schemas/common.yaml#/$defs/Pet/properties/kind/type',
        'file:///schemas/draft7.json#/exclusiveMaximum'
      ],
      error_locations(errors).sort
    )
    assert_equal(['PathItem', 'Schema'], errors.map { |error| error.fetch('expected') }.uniq.sort)
  end

  def test_openapi_31_identifiers_found_in_any_order
    documents = {
      'file:///openapi.yaml' => {
        'openapi' => '3.1.0',
        'info' => INFO,
        'components' => {
          'schemas' => {
            # referred to before the document declaring it is reached
            'A' => { '$ref' => 'https://example.com/b' },
            'B' => { '$ref' => 'b.yaml' }
          }
        }
      },
      'file:///b.yaml' => { '$defs' => { 'b' => { '$id' => 'https://example.com/b', 'type' => 'string' } } }
    }
    assert_equal([], deep_errors(documents))
    documents['file:///b.yaml']['$defs']['b']['type'] = 'strng'
    # located in the document declaring the identifier
    assert_equal(['file:///b.yaml#/$defs/b/type'], error_locations(deep_errors(documents)))
  end

  def test_json_schema_dialect
    documents = {
      'file:///openapi.yaml' => {
        'openapi' => '3.1.0',
        'info' => INFO,
        'jsonSchemaDialect' => 'https://json-schema.org/draft/2020-12/schema',
        'components' => { 'schemas' => { 'A' => { '$ref' => 'a.yaml' } } }
      },
      'file:///a.yaml' => { 'type' => 'object', 'discriminator' => 'not checked by 2020-12' }
    }
    assert_equal([], deep_errors(documents))
    documents['file:///openapi.yaml'].delete('jsonSchemaDialect')
    assert_equal(['file:///a.yaml#/discriminator'], error_locations(deep_errors(documents)))
  end

  def test_discriminator_mapping
    documents = {
      'file:///openapi.yaml' => {
        'openapi' => '3.0.3',
        'info' => INFO,
        'paths' => {},
        'components' => {
          'schemas' => {
            'Pet' => { '$ref' => 'pet.yaml' },
            'Cat' => { 'type' => 'object' }
          }
        }
      },
      'file:///pet.yaml' => {
        'type' => 'object',
        'discriminator' => { 'propertyName' => 'kind', 'mapping' => { 'cat' => 'Cat', 'dog' => 'Dog', 'bird' => 'bird.yaml', 'fish' => 'fish.yaml' } },
        'oneOf' => [{ '$ref' => 'openapi.yaml#/components/schemas/Cat' }]
      },
      'file:///bird.yaml' => { 'type' => 'object', 'properties' => { 'wings' => { 'type' => 'integr' } } }
    }
    errors = deep_errors(documents)
    assert_equal(
      [
        'file:///bird.yaml#/properties/wings',
        'file:///bird.yaml#/properties/wings/type',
        'file:///pet.yaml#/discriminator/mapping/dog',
        'file:///pet.yaml#/discriminator/mapping/fish'
      ],
      error_locations(errors).sort
    )
    assert_includes(errors.map { |error| error.fetch('error') }, "value at `/discriminator/mapping/dog` references `file:///openapi.yaml#/components/schemas/Dog`, but pointer `/components/schemas/Dog` doesn't exist in `file:///openapi.yaml`")
  end

  def test_openapi_32
    documents = {
      'file:///api/openapi.yaml' => {
        'openapi' => '3.2.0',
        '$self' => 'https://example.com/api/openapi.yaml',
        'info' => INFO,
        'paths' => {
          '/search' => {
            'query' => { 'requestBody' => { '$ref' => '#/components/requestBodies/Search' }, 'responses' => { '200' => { 'description' => 'OK' } } },
            'additionalOperations' => { 'COPY' => { 'responses' => { '200' => { '$ref' => 'common.yaml#/Copied' } } } }
          }
        },
        'components' => {
          'requestBodies' => {
            'Search' => { 'content' => { 'application/jsonl' => { '$ref' => '#/components/mediaTypes/Lines' } } }
          },
          'mediaTypes' => {
            'Lines' => { 'itemSchema' => { '$ref' => 'common.yaml#/Line' } }
          }
        }
      },
      # `$self` is the base URI of the entry document
      'https://example.com/api/common.yaml' => {
        'Copied' => { 'description' => 'Copied' },
        'Line' => { 'type' => 'object' }
      }
    }
    assert_equal([], deep_errors(documents, 'file:///api/openapi.yaml'))
    documents['https://example.com/api/common.yaml']['Line']['type'] = 'objct'
    documents['https://example.com/api/common.yaml']['Copied']['content'] = 'none'
    assert_equal(
      ['https://example.com/api/common.yaml#/Copied/content', 'https://example.com/api/common.yaml#/Line/type'],
      error_locations(deep_errors(documents, 'file:///api/openapi.yaml')).sort
    )
  end

  def test_max_documents
    documents = fixture_documents(File.join(FIXTURES, 'split'))
    assert(openapi(documents).valid?(:deep => true, :max_documents => 6))
    errors = deep_errors(documents, :max_documents => 2)
    refute_empty(errors)
    assert(errors.all? { |error| error.fetch('error').end_with?("which can't be retrieved: more than 2 documents referenced") })
  end

  def test_callbacks
    documents = {
      'file:///openapi.yaml' => {
        'openapi' => '3.0.3',
        'info' => INFO,
        'paths' => {
          '/subscribe' => {
            'post' => {
              'callbacks' => {
                'inline' => { '{$request.body#/url}' => { 'post' => { 'responses' => { '200' => { '$ref' => 'common.yaml#/OK' } } } }, 'x-note' => 'skipped' },
                'shared' => { '$ref' => 'common.yaml#/Callback' }
              },
              'responses' => { '200' => { 'description' => 'OK' } }
            }
          }
        }
      },
      'file:///common.yaml' => {
        'OK' => { 'description' => 'OK' },
        'Callback' => { '{$request.body#/url}' => { 'post' => { 'responses' => { '200' => { 'description' => 1 } } } } }
      }
    }
    errors = deep_errors(documents)
    assert_equal(['file:///common.yaml#/Callback/%7B$request.body%23~1url%7D/post/responses/200/description'], error_locations(errors).select { |location| location.end_with?('description') })
    assert_equal(['Callback'], errors.map { |error| error.fetch('expected') }.uniq)
  end

  def test_schema_and_document_compile_errors
    documents = {
      'file:///openapi.yaml' => {
        'openapi' => '3.1.0',
        'info' => INFO,
        'components' => {
          'parameters' => { 'P' => { '$ref' => 'parameters.yaml#/P' } },
          'schemas' => { 'S' => { '$ref' => 'schema.yaml' } }
        }
      },
      # a document whose Schema Objects can't be compiled
      'file:///parameters.yaml' => {
        '$vocabulary' => { 'https://example.com/unknown' => true },
        'P' => { 'name' => 'p', 'in' => 'query', 'schema' => { 'type' => 'string' } }
      },
      # a schema of its own with an unknown dialect, reached through a parameter's schema
      'file:///schema.yaml' => { '$schema' => 'https://example.com/unknown' }
    }
    errors = deep_errors(documents)
    assert_includes(errors.map { |error| [error.fetch('absoluteInstanceLocation'), error.fetch('error')] }, ['file:///parameters.yaml#', "value at root schema can't be compiled: https://example.com/unknown"])
    assert_includes(errors.map { |error| error.fetch('error') }, "value at `/components/schemas/S/$ref` references `schema.yaml`, which can't be resolved: `https://example.com/unknown` can't be retrieved")

    documents['file:///openapi.yaml']['components']['schemas']['S'] = { 'properties' => { 'a' => { '$ref' => 'schema.yaml' } } }
    documents['file:///parameters.yaml'].delete('$vocabulary')
    documents['file:///parameters.yaml']['P']['schema'] = { '$ref' => 'schema.yaml' }
    errors = deep_errors(documents)
    assert(errors.any? { |error| error.fetch('absoluteInstanceLocation') == 'file:///openapi.yaml#/components/schemas/S/properties/a/$ref' })
  end

  def test_unknown_schema_dialect
    documents = {
      'file:///openapi.yaml' => {
        'openapi' => '3.1.0',
        'info' => INFO,
        'components' => { 'parameters' => { 'P' => { '$ref' => 'parameters.yaml#/P' } } }
      },
      'file:///parameters.yaml' => { 'P' => { 'name' => 'p', 'in' => 'query', 'schema' => { '$schema' => 'https://example.com/unknown' } } }
    }
    errors = deep_errors(documents)
    assert_equal(['file:///parameters.yaml#/P/schema'], error_locations(errors))
    assert_match(/\Avalue at `\/P\/schema` has an unknown meta schema: /, errors.first.fetch('error'))
  end

  def test_invalid_schema_reference
    documents = {
      'file:///openapi.yaml' => {
        'openapi' => '3.0.3',
        'info' => INFO,
        'paths' => {},
        'components' => { 'schemas' => { 'A' => { 'properties' => { 'a' => { '$ref' => 'http://[bad' } } } } }
      }
    }
    errors = deep_errors(documents).select { |error| error.key?('ref') }
    assert_equal(['file:///openapi.yaml#/components/schemas/A/properties/a/$ref'], error_locations(errors))
    assert_match(/has an invalid reference `http:\/\/\[bad`: /, errors.first.fetch('error'))
  end

  def test_without_base_uri
    document = { 'openapi' => '3.1.0', 'info' => INFO, 'components' => { 'schemas' => { 'A' => { '$ref' => '#missing' }, 'B' => { '$ref' => 'b.yaml' } } } }
    errors = JSONSchemer.openapi(document).validate(:deep => true, :output_format => 'basic').fetch('errors')
    assert_equal(
      [
        "value at `/components/schemas/A/$ref` references `#missing`, which doesn't exist in `json-schemer://schema`",
        "value at `/components/schemas/B/$ref` references `b.yaml`, which can't be retrieved: json-schemer://schema/b.yaml"
      ],
      errors.map { |error| error.fetch('error') }
    )
  end

  def test_identifier_declared_twice
    documents = {
      'file:///openapi.yaml' => {
        'openapi' => '3.1.0',
        'info' => INFO,
        'components' => { 'schemas' => { 'A' => { '$ref' => 'a.yaml' }, 'B' => { '$ref' => 'b.yaml' }, 'C' => { '$ref' => 'https://example.com/c' } } }
      },
      'file:///a.yaml' => { '$defs' => { 'c' => { '$id' => 'https://example.com/c', 'type' => 'string' } } },
      'file:///b.yaml' => { '$defs' => { 'c' => { '$id' => 'https://example.com/c', 'type' => 'strng' } } }
    }
    # the first declaration found wins
    assert_equal(['file:///b.yaml#/$defs/c/type'], error_locations(deep_errors(documents)))
  end

  def test_invalid_self
    documents = {
      'file:///openapi.yaml' => {
        'openapi' => '3.2.0',
        '$self' => 'http://[bad',
        'info' => INFO,
        'components' => { 'responses' => { 'R' => { '$ref' => 'common.yaml#/R' } } }
      },
      'file:///common.yaml' => { 'R' => { 'content' => 'none' } }
    }
    # `$self` reported by the document schema, the retrieval URI used instead
    assert_equal(['file:///openapi.yaml#/$self', 'file:///common.yaml#/R/content'], error_locations(deep_errors(documents)))
  end

  def test_discriminator_mapping_values
    documents = {
      'file:///openapi.yaml' => {
        'openapi' => '3.1.0',
        'info' => INFO,
        'components' => {
          'schemas' => {
            'Pet' => { 'discriminator' => { 'propertyName' => 'kind', 'mapping' => { 'number' => 5, 'file' => 'cat.yaml' } } }
          }
        }
      },
      'file:///cat.yaml' => { 'type' => 'objct' }
    }
    # a name that's not a component is a URI reference
    assert_includes(error_locations(deep_errors(documents)), 'file:///cat.yaml#/type')
  end

  def test_schema_errors
    documents = {
      'file:///openapi.yaml' => {
        'openapi' => '3.1.0',
        'info' => INFO,
        'components' => {
          'schemas' => {
            'Unknown' => { '$schema' => 'https://example.com/unknown' },
            'Missing' => { '$ref' => 'missing.yaml' },
            'Pointer' => { '$ref' => 'a.yaml#/$defs/missing' },
            'Anchor' => { '$ref' => 'a.yaml#missing' },
            'Vocabulary' => { '$ref' => 'vocabulary.yaml' },
            'LocalAnchor' => { '$ref' => '#missing' }
          }
        }
      },
      'file:///a.yaml' => { '$defs' => {} },
      'file:///vocabulary.yaml' => { '$vocabulary' => { 'https://example.com/unknown' => true } }
    }
    errors = deep_errors(documents)
    messages = errors.map { |error| error.fetch('error') }
    # the root document's dialect enum and the compiled schema
    assert_includes(error_locations(errors), 'file:///openapi.yaml#/components/schemas/Unknown/$schema')
    assert_includes(messages, "value at `/components/schemas/Unknown` schema can't be compiled: https://example.com/unknown")
    assert_includes(messages, "value at `/components/schemas/Missing/$ref` references `missing.yaml`, which can't be retrieved: not found")
    assert_includes(messages, "value at `/components/schemas/Pointer/$ref` references `a.yaml#/$defs/missing`, but pointer `/$defs/missing` doesn't exist in `file:///a.yaml`")
    assert_includes(messages, "value at `/components/schemas/Anchor/$ref` references `a.yaml#missing`, which doesn't exist in `file:///a.yaml`")
    assert_includes(messages, "value at `/components/schemas/Vocabulary/$ref` references `vocabulary.yaml`, which can't be resolved: https://example.com/unknown")
    assert_includes(messages, "value at `/components/schemas/LocalAnchor/$ref` references `#missing`, which doesn't exist in `file:///openapi.yaml`")
  end
end
