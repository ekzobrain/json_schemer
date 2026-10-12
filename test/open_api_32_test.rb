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

  def pet_openapi(keyword, discriminator, version: '3.2.0', **options)
    JSONSchemer.openapi(
      {
        'openapi' => version,
        'info' => INFO,
        'components' => {
          'schemas' => PETS.merge(
            'Pet' => {
              keyword => PETS.keys.map { |name| { '$ref' => "#/components/schemas/#{name}" } },
              'discriminator' => discriminator
            }
          )
        }
      },
      **options
    )
  end

  def pet_schemer(*args, **options)
    pet_openapi(*args, **options).schema('Pet')
  end

  def schema_pointers(schemer, instance)
    schemer.validate(instance).map { |error| error.fetch('schema_pointer') }
  end

  def test_discriminator_doesnt_change_validation_outcome
    ['oneOf', 'anyOf'].each do |keyword|
      schemer = pet_schemer(keyword, { 'propertyName' => 'petType' })
      assert(schemer.valid_schema?)
      assert(schemer.valid?({ 'petType' => 'Cat', 'name' => 'misty' }))
      refute(schemer.valid?({ 'petType' => 'Cat', 'name' => 1 }))
      # missing or unmapped discriminating property: `OtherPet` matches
      assert(schemer.valid?({ 'legs' => 4 }))
      assert(schemer.valid?({ 'petType' => 'Hamster', 'legs' => 4 }))
      refute(schemer.valid?({ 'petType' => 'Hamster', 'legs' => 'four' }))
      refute(schemer.valid?(1))
    end
  end

  def test_discriminator_one_of_with_several_matching_schemas
    document = {
      'openapi' => '3.2.0',
      'info' => INFO,
      'components' => {
        'schemas' => {
          'a' => { 'properties' => { 'type' => { 'const' => 'a' } } },
          'b' => { 'properties' => { 'count' => { 'type' => 'integer' } } },
          'ab' => { 'oneOf' => [{ '$ref' => '#/components/schemas/a' }, { '$ref' => '#/components/schemas/b' }], 'discriminator' => { 'propertyName' => 'type' } }
        }
      }
    }
    # matches both `a` and `b`
    refute(JSONSchemer.openapi(document).schema('ab').valid?({ 'type' => 'a' }))
    assert(JSONSchemer.openapi(document.merge('openapi' => '3.1.0')).schema('ab').valid?({ 'type' => 'a' }))
    assert(JSONSchemer.openapi(document).schema('ab').valid?({ 'type' => 'a', 'count' => 'one' }))
  end

  def test_discriminator_errors
    ['oneOf', 'anyOf'].each do |keyword|
      schemer = pet_schemer(keyword, { 'propertyName' => 'petType' })
      # only the errors of the discriminated schema
      assert_equal(['/components/schemas/Cat/properties/name'], schema_pointers(schemer, { 'petType' => 'Cat', 'name' => 1 }))
      assert_equal(['/components/schemas/Dog/properties/bark'], schema_pointers(schemer, { 'petType' => 'Dog', 'bark' => 1 }))
      # no discriminated schema: errors of all subschemas
      assert_equal(
        ['/components/schemas/Cat/properties/petType', '/components/schemas/Dog/properties/petType', '/components/schemas/OtherPet/properties/legs'],
        schema_pointers(schemer, { 'petType' => 'Hamster', 'legs' => 'four' }).sort
      )
      assert_equal(['/components/schemas/Cat', '/components/schemas/Dog', '/components/schemas/OtherPet/properties/legs'], schema_pointers(schemer, { 'legs' => 'four' }).sort)
      assert_equal(['/components/schemas/Cat', '/components/schemas/Dog', '/components/schemas/OtherPet'], schema_pointers(schemer, 1).sort)
    end
  end

  def test_discriminator_default_mapping
    ['oneOf', 'anyOf'].each do |keyword|
      ['OtherPet', '#/components/schemas/OtherPet'].each do |default_mapping|
        schemer = pet_schemer(keyword, { 'propertyName' => 'petType', 'defaultMapping' => default_mapping })
        assert(schemer.valid_schema?)
        assert(schemer.valid?({ 'petType' => 'Cat', 'name' => 'misty' }))
        assert(schemer.valid?({ 'legs' => 4 }))
        assert(schemer.valid?({ 'petType' => 'Hamster', 'legs' => 4 }))
        assert_equal(['/components/schemas/Cat/properties/name'], schema_pointers(schemer, { 'petType' => 'Cat', 'name' => 1 }))
        # missing or unmapped discriminating property: errors of the `defaultMapping` schema
        assert_equal(['/components/schemas/OtherPet/properties/legs'], schema_pointers(schemer, { 'legs' => 'four' }))
        assert_equal(['/components/schemas/OtherPet/properties/legs'], schema_pointers(schemer, { 'petType' => 'Hamster', 'legs' => 'four' }))
      end
    end
  end

  def test_discriminator_unknown_default_mapping
    schemer = pet_schemer('oneOf', { 'propertyName' => 'petType', 'defaultMapping' => 'Hamster' })
    assert(schemer.valid?({ 'legs' => 4 }))
    assert_equal(3, schema_pointers(schemer, { 'legs' => 'four' }).size)
  end

  def test_discriminator_default_mapping_without_property_name
    schemer = pet_schemer('oneOf', { 'defaultMapping' => 'OtherPet' })
    assert(schemer.valid?({ 'legs' => 4 }))
    assert_equal(['/components/schemas/OtherPet/properties/legs'], schema_pointers(schemer, { 'legs' => 'four' }))
  end

  def test_discriminator_inline_subschemas
    schemer = JSONSchemer.openapi({
      'openapi' => '3.2.0',
      'info' => INFO,
      'components' => {
        'schemas' => {
          'Cat' => PETS.fetch('Cat'),
          'Pet' => { 'oneOf' => [{ 'required' => ['legs'] }, { '$ref' => '#/components/schemas/Cat' }], 'discriminator' => { 'propertyName' => 'petType', 'defaultMapping' => 'Cat' } }
        }
      }
    }).schema('Pet')
    assert(schemer.valid?({ 'petType' => 'Cat' }))
    assert(schemer.valid?({ 'legs' => 4 }))
    assert_equal(['/components/schemas/Cat/properties/name'], schema_pointers(schemer, { 'petType' => 'Cat', 'name' => 1 }))
    assert_equal(['/components/schemas/Cat', '/components/schemas/Cat/properties/name'], schema_pointers(schemer, { 'name' => 1 }).sort)
  end

  def test_all_of_discriminator
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
    # the parent schema doesn't use child schemas
    assert(openapi.schema('Pet').valid?({ 'petType' => 'dog', 'bark' => 1 }))
    assert(openapi.schema('Pet').valid?({ 'legs' => 'four' }))
    refute(openapi.schema('Pet').valid?({ 'petType' => 1 }))
    assert(openapi.schema('Dog').valid?({ 'petType' => 'dog', 'bark' => 'soft' }))
    assert_equal(['/components/schemas/Dog/allOf/1/properties/bark'], schema_pointers(openapi.schema('Dog'), { 'petType' => 'dog', 'bark' => 1 }))
    assert_equal(['/components/schemas/Pet/properties/petType'], schema_pointers(openapi.schema('Dog'), { 'petType' => 1 }))
    assert(openapi.schema('OtherPet').valid?({ 'legs' => 4 }))
    refute(openapi.schema('OtherPet').valid?({ 'legs' => 'four' }))
  end

  def test_discriminator_fast_path
    schemer = pet_schemer('oneOf', { 'propertyName' => 'petType' })
    assert_equal(true, schemer.send(:validate_instance_boolean, { 'legs' => 4 }))
    assert_equal(false, schemer.send(:validate_instance_boolean, { 'legs' => 'four' }))
    assert_nil(pet_schemer('oneOf', { 'propertyName' => 'petType' }, :version => '3.1.0').send(:validate_instance_boolean, { 'legs' => 4 }))
  end

  def test_discriminator_mode_by_version
    discriminator = { 'propertyName' => 'petType' }
    ['3.0.3', '3.1.0'].each do |version|
      schemer = pet_schemer('oneOf', discriminator, :version => version)
      refute(schemer.valid?({ 'legs' => 4 }), version)
      assert(schemer.valid?({ 'petType' => 'OtherPet', 'legs' => 4 }), version)
    end
    ['3.1.1', '3.1.2', '3.2.0'].each do |version|
      schemer = pet_schemer('oneOf', discriminator, :version => version)
      assert(schemer.valid?({ 'legs' => 4 }), version)
      assert(schemer.valid?({ 'petType' => 'OtherPet', 'legs' => 4 }), version)
    end
    # 3.2 document with the 3.1 dialect
    document = { 'openapi' => '3.2.0', 'info' => INFO, 'jsonSchemaDialect' => JSONSchemer::OpenAPI31::BASE_URI.to_s, 'components' => { 'schemas' => PETS.merge('Pet' => { 'oneOf' => PETS.keys.map { |name| { '$ref' => "#/components/schemas/#{name}" } }, 'discriminator' => discriminator }) } }
    assert(JSONSchemer.openapi(document).schema('Pet').valid?({ 'legs' => 4 }))
  end

  def test_discriminator_mode_option
    select = pet_schemer('oneOf', { 'propertyName' => 'petType', 'defaultMapping' => 'OtherPet' }, :discriminator_mode => 'select')
    assert(select.valid?({ 'legs' => 4 }))
    assert(select.valid?({ 'petType' => 'Hamster', 'legs' => 4 }))
    assert_equal(['/components/schemas/OtherPet/properties/legs'], schema_pointers(select, { 'legs' => 'four' }))
    assert(select.valid?({ 'petType' => 'OtherPet', 'legs' => 4 }))

    select_without_default = pet_schemer('oneOf', { 'propertyName' => 'petType' }, :discriminator_mode => 'select')
    refute(select_without_default.valid?({ 'legs' => 4 }))

    hint = pet_schemer('oneOf', { 'propertyName' => 'petType' }, :version => '3.1.0', :discriminator_mode => 'hint')
    assert(hint.valid?({ 'legs' => 4 }))

    # without `JSONSchemer.openapi`, by dialect
    schema = { 'oneOf' => [{ '$ref' => '#/$defs/a' }, { '$ref' => '#/$defs/b' }], 'discriminator' => { 'propertyName' => 'type', 'mapping' => { 'a' => '#/$defs/a' } }, '$defs' => { 'a' => true, 'b' => true } }
    assert(JSONSchemer.schema(schema, :meta_schema => JSONSchemer.openapi31).valid?({ 'type' => 'a' }))
    refute(JSONSchemer.schema(schema, :meta_schema => JSONSchemer.openapi32).valid?({ 'type' => 'a' }))
    refute(JSONSchemer.schema(schema, :meta_schema => JSONSchemer.openapi31, :discriminator_mode => 'hint').valid?({ 'type' => 'a' }))
    assert(JSONSchemer.schema(schema, :meta_schema => JSONSchemer.openapi32, :discriminator_mode => 'select').valid?({ 'type' => 'a' }))
  end

  def test_all_of_discriminator_default_mapping_select_mode
    openapi = JSONSchemer.openapi(
      {
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
      },
      :discriminator_mode => 'select'
    )
    schemer = openapi.schema('Pet')
    assert(schemer.valid?({ 'petType' => 'dog', 'bark' => 'soft' }))
    assert_equal(['/components/schemas/Dog/allOf/1/properties/bark'], schema_pointers(schemer, { 'petType' => 'dog', 'bark' => 1 }))
    assert(schemer.valid?({ 'legs' => 4 }))
    assert_equal(['/components/schemas/OtherPet/allOf/1/properties/legs'], schema_pointers(schemer, { 'legs' => 'four' }))
    assert_equal(['/components/schemas/OtherPet/allOf/1/properties/legs'], schema_pointers(schemer, { 'petType' => 'hamster', 'legs' => 'four' }))
    assert(openapi.schema('OtherPet').valid?({ 'legs' => 4 }))
  end

  def test_openapi_310_discriminator_ignores_default_mapping
    refute(pet_schemer('oneOf', { 'propertyName' => 'petType', 'defaultMapping' => 'OtherPet' }, :version => '3.1.0').valid?({ 'legs' => 4 }))
  end
end
