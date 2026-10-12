require 'test_helper'

class OpenAPI32Test < Minitest::Test
  INFO = { 'title' => 'test', 'version' => '1.0' }.freeze
  OK_RESPONSES = { '200' => { 'description' => 'OK' } }.freeze
  MAX_INT32 = 2.pow(31) - 1

  # Fields added in OpenAPI 3.2, as [description, document fields]
  OPENAPI_32_FIELDS = [
    ['$self', { '$self' => 'https://example.com/api/openapi.json', 'paths' => {} }],
    ['server name', { 'servers' => [{ 'url' => 'https://api.example.com', 'name' => 'production' }], 'paths' => {} }],
    ['path item query', { 'paths' => { '/search' => { 'query' => { 'responses' => OK_RESPONSES } } } }],
    ['path item additionalOperations', { 'paths' => { '/search' => { 'additionalOperations' => { 'COPY' => { 'responses' => OK_RESPONSES } } } } }],
    ['components mediaTypes', { 'components' => { 'mediaTypes' => { 'jsonBody' => { 'schema' => { 'type' => 'object' } } } } }],
    ['example dataValue and serializedValue', { 'components' => { 'examples' => { 'sample' => { 'dataValue' => { 'id' => 1 }, 'serializedValue' => '{"id":1}' } } } }],
    ['querystring parameter', { 'components' => { 'parameters' => { 'qs' => { 'name' => 'qs', 'in' => 'querystring', 'content' => { 'application/x-www-form-urlencoded' => { 'schema' => { 'type' => 'object' } } } } } } }],
    ['tag parent and kind', { 'tags' => [{ 'name' => 'cats', 'parent' => 'pets', 'kind' => 'nav' }], 'paths' => {} }],
    ['response summary without description', { 'components' => { 'responses' => { 'ok' => { 'summary' => 'OK' } } } }],
    ['discriminator defaultMapping', { 'components' => { 'schemas' => { 'pet' => { 'oneOf' => [{ '$ref' => '#/components/schemas/other' }], 'discriminator' => { 'propertyName' => 'petType', 'defaultMapping' => 'other' } }, 'other' => true } } }],
    ['xml nodeType', { 'components' => { 'schemas' => { 'pet' => { 'xml' => { 'nodeType' => 'element' } } } } }]
  ].freeze

  def test_openapi_32_fields
    OPENAPI_32_FIELDS.each do |description, fields|
      assert(JSONSchemer.openapi({ 'openapi' => '3.2.0', 'info' => INFO }.merge(fields)).valid?, "#{description} is valid in 3.2")
      refute(JSONSchemer.openapi({ 'openapi' => '3.1.0', 'info' => INFO }.merge(fields)).valid?, "#{description} is invalid in 3.1")
    end
  end

  def test_openapi_32_document_errors
    refute(JSONSchemer.openapi({ 'openapi' => '3.2.0', 'info' => INFO }).valid?)
    refute(JSONSchemer.openapi({ 'openapi' => '3.2.0', 'info' => INFO, 'paths' => {}, '$self' => 'https://example.com/openapi.json#fragment' }).valid?)
    refute(JSONSchemer.openapi({ 'openapi' => '3.2.0', 'info' => INFO, 'components' => { 'schemas' => { 'pet' => { 'xml' => { 'nodeType' => 'bogus' } } } } }).valid?)
    refute(JSONSchemer.openapi({ 'openapi' => '3.2.0', 'info' => INFO, 'components' => { 'schemas' => { 'pet' => { 'type' => 1 } } } }).valid?)
    assert_equal(
      ['/paths/~1search/unknown'],
      JSONSchemer.openapi({ 'openapi' => '3.2.0', 'info' => INFO, 'paths' => { '/search' => { 'unknown' => {} } } }).validate.map { |error| error.fetch('data_pointer') }
    )
  end

  def test_openapi_versions
    assert(JSONSchemer.openapi({ 'openapi' => '3.2.1', 'info' => INFO, 'paths' => {} }).valid?)
    assert(JSONSchemer.openapi({ 'openapi' => '3.1.0', 'info' => INFO, 'paths' => {} }).valid?)
    assert_raises(JSONSchemer::UnsupportedOpenAPIVersion) { JSONSchemer.openapi({ 'openapi' => '3.3.0', 'info' => INFO, 'paths' => {} }) }
    assert_raises(JSONSchemer::UnsupportedOpenAPIVersion) { JSONSchemer.openapi({ 'openapi' => '3.2', 'info' => INFO, 'paths' => {} }) }
  end

  def test_json_schema_dialects
    schemas = {
      'widget' => { 'type' => 'object', 'properties' => { 'count' => { 'type' => 'integer', 'format' => 'int32' } } }
    }

    [
      nil,
      JSONSchemer::OpenAPI32::BASE_URI.to_s,
      JSONSchemer::OpenAPI31::BASE_URI.to_s,
      JSONSchemer::Draft202012::BASE_URI.to_s
    ].each do |dialect|
      document = { 'openapi' => '3.2.0', 'info' => INFO, 'components' => { 'schemas' => schemas } }
      document['jsonSchemaDialect'] = dialect if dialect
      openapi = JSONSchemer.openapi(document)
      assert(openapi.valid?, dialect)
      assert(openapi.schema('widget').valid?({ 'count' => 1 }))
      refute(openapi.schema('widget').valid?({ 'count' => 'one' }))
      assert_equal(
        dialect != JSONSchemer::Draft202012::BASE_URI.to_s,
        !openapi.schema('widget').valid?({ 'count' => MAX_INT32 + 1 }),
        "int32 format with #{dialect.inspect}"
      )
    end

    assert_raises(JSONSchemer::UnknownRef) { JSONSchemer.openapi({ 'openapi' => '3.2.0', 'jsonSchemaDialect' => 'unsupported' }) }
  end

  def test_document_validates_schemas_with_dialect
    document = {
      'openapi' => '3.2.0',
      'info' => INFO,
      'components' => {
        'schemas' => {
          'draft4' => { '$schema' => JSONSchemer::Draft4::BASE_URI.to_s, 'exclusiveMaximum' => true, 'maximum' => 1 }
        }
      }
    }
    assert(JSONSchemer.openapi(document).valid?)
    refute(JSONSchemer.openapi(document.merge('jsonSchemaDialect' => JSONSchemer::Draft202012::BASE_URI.to_s, 'components' => { 'schemas' => { 'x' => { 'exclusiveMaximum' => true } } })).valid?)
  end

  def test_meta_schema
    assert(JSONSchemer.openapi32.valid_schema?)
    schemer = JSONSchemer.schema({ '$schema' => JSONSchemer::OpenAPI32::BASE_URI.to_s, 'type' => 'integer', 'format' => 'int32' })
    assert_equal(JSONSchemer.openapi32, schemer.meta_schema)
    assert(schemer.valid?(1))
    refute(schemer.valid?(MAX_INT32 + 1))
    assert(JSONSchemer.valid_schema?({ '$schema' => JSONSchemer::OpenAPI32::BASE_URI.to_s, 'xml' => { 'nodeType' => 'attribute' } }))
    refute(JSONSchemer.valid_schema?({ '$schema' => JSONSchemer::OpenAPI32::BASE_URI.to_s, 'xml' => { 'nodeType' => 'bogus' } }))
    refute(JSONSchemer.valid_schema?({ '$schema' => JSONSchemer::OpenAPI32::BASE_URI.to_s, 'xml' => { 'nodeType' => 'element', 'attribute' => true } }))
    assert(JSONSchemer.valid_schema?({ '$schema' => JSONSchemer::OpenAPI32::BASE_URI.to_s, 'discriminator' => { 'propertyName' => 'x', 'defaultMapping' => 'y' } }))
  end


  PETS = {
    'Cat' => { 'type' => 'object', 'required' => ['petType'], 'properties' => { 'petType' => { 'const' => 'Cat' }, 'name' => { 'type' => 'string' } } },
    'Dog' => { 'type' => 'object', 'required' => ['petType'], 'properties' => { 'petType' => { 'const' => 'Dog' }, 'bark' => { 'type' => 'string' } } },
    'OtherPet' => { 'type' => 'object', 'properties' => { 'petType' => { 'not' => { 'enum' => ['Cat', 'Dog'] } }, 'legs' => { 'type' => 'integer' } } }
  }.freeze

  def pet_schemer(keyword, discriminator)
    JSONSchemer.openapi({
      'openapi' => '3.2.0',
      'info' => INFO,
      'components' => {
        'schemas' => PETS.merge(
          'Pet' => {
            keyword => PETS.keys.map { |name| { '$ref' => "#/components/schemas/#{name}" } },
            'discriminator' => discriminator
          }
        )
      }
    }).schema('Pet')
  end

  def test_discriminator_default_mapping
    ['oneOf', 'anyOf'].each do |keyword|
      ['OtherPet', '#/components/schemas/OtherPet'].each do |default_mapping|
        schemer = pet_schemer(keyword, { 'propertyName' => 'petType', 'defaultMapping' => default_mapping })
        assert(schemer.valid_schema?)
        assert(schemer.valid?({ 'petType' => 'Cat', 'name' => 'misty' }))
        assert_equal(['/components/schemas/Cat/properties/name'], schemer.validate({ 'petType' => 'Cat', 'name' => 1 }).map { |error| error.fetch('schema_pointer') })
        # missing or unmapped discriminating property: `defaultMapping` schema
        assert(schemer.valid?({ 'legs' => 4 }))
        assert(schemer.valid?({ 'petType' => 'Hamster', 'legs' => 4 }))
        assert_equal(['/components/schemas/OtherPet/properties/legs'], schemer.validate({ 'legs' => 'four' }).map { |error| error.fetch('schema_pointer') })
        assert_equal(['/components/schemas/OtherPet/properties/legs'], schemer.validate({ 'petType' => 'Hamster', 'legs' => 'four' }).map { |error| error.fetch('schema_pointer') })
        refute(schemer.valid?(1))
      end
    end
  end

  def test_discriminator_without_default_mapping
    schemer = pet_schemer('oneOf', { 'propertyName' => 'petType' })
    assert(schemer.valid?({ 'petType' => 'Cat' }))
    assert(schemer.valid?({ 'petType' => 'OtherPet', 'legs' => 4 }))
    refute(schemer.valid?({ 'legs' => 4 }))
    refute(schemer.valid?({ 'petType' => 'Hamster' }))
  end

  def test_discriminator_unknown_default_mapping
    schemer = pet_schemer('oneOf', { 'propertyName' => 'petType', 'defaultMapping' => 'Hamster' })
    assert(schemer.valid?({ 'petType' => 'Cat' }))
    refute(schemer.valid?({ 'legs' => 4 }))
  end

  def test_discriminator_default_mapping_without_property_name
    schemer = pet_schemer('oneOf', { 'defaultMapping' => 'OtherPet' })
    assert(schemer.valid?({ 'legs' => 4 }))
    refute(schemer.valid?({ 'legs' => 'four' }))
  end

  def test_all_of_discriminator_default_mapping
    openapi = JSONSchemer.openapi({
      'openapi' => '3.2.0',
      'info' => INFO,
      'components' => {
        'schemas' => {
          'Pet' => {
            'type' => 'object',
            'properties' => { 'petType' => { 'type' => 'string' } },
            'discriminator' => { 'propertyName' => 'petType', 'mapping' => { 'dog' => 'Dog' }, 'defaultMapping' => 'OtherPet' }
          },
          'Dog' => { 'allOf' => [{ '$ref' => '#/components/schemas/Pet' }, { 'properties' => { 'bark' => { 'type' => 'string' } } }] },
          'OtherPet' => { 'allOf' => [{ '$ref' => '#/components/schemas/Pet' }, { 'properties' => { 'legs' => { 'type' => 'integer' } } }] }
        }
      }
    })
    schemer = openapi.schema('Pet')
    assert(schemer.valid?({ 'petType' => 'dog', 'bark' => 'soft' }))
    assert_equal(['/components/schemas/Dog/allOf/1/properties/bark'], schemer.validate({ 'petType' => 'dog', 'bark' => 1 }).map { |error| error.fetch('schema_pointer') })
    assert(schemer.valid?({ 'legs' => 4 }))
    assert_equal(['/components/schemas/OtherPet/allOf/1/properties/legs'], schemer.validate({ 'legs' => 'four' }).map { |error| error.fetch('schema_pointer') })
    assert_equal(['/components/schemas/OtherPet/allOf/1/properties/legs'], schemer.validate({ 'petType' => 'hamster', 'legs' => 'four' }).map { |error| error.fetch('schema_pointer') })
    assert(openapi.schema('OtherPet').valid?({ 'legs' => 4 }))
  end

  def test_openapi_31_discriminator_ignores_default_mapping
    openapi = {
      'openapi' => '3.1.0',
      'info' => INFO,
      'components' => {
        'schemas' => PETS.merge('Pet' => { 'oneOf' => PETS.keys.map { |name| { '$ref' => "#/components/schemas/#{name}" } }, 'discriminator' => { 'propertyName' => 'petType', 'defaultMapping' => 'OtherPet' } })
      }
    }
    refute(JSONSchemer.openapi(openapi).schema('Pet').valid?({ 'legs' => 4 }))
  end
end
