require 'test_helper'

class HooksTest < Minitest::Test
  def test_it_can_insert_symbol_keys
    schema = {
      'properties' => {
        'a' => {
          'default' => 'x'
        }
      }
    }

    schemer = JSONSchemer.schema(schema, insert_property_defaults: true)
    instance = {}
    schemer.validate(instance)
    refute(instance.key?(:a))
    assert_equal('x', instance.fetch('a'))

    schemer = JSONSchemer.schema(schema, insert_property_defaults: :symbol)
    instance = {}
    schemer.validate(instance)
    refute(instance.key?('a'))
    assert_equal('x', instance.fetch(:a))
  end

  def test_it_calls_before_validation_hooks_to_modify_data
    parse_array = proc do |data, property, property_schema, _|
      if data.key?(property) && property_schema.is_a?(Hash) && property_schema['type'] == 'array'
        parsed = data[property].split(',')
        parsed = parsed.map!(&:to_i) if property_schema['items']['type'] == 'integer'
        data[property] = parsed
      end
    end
    data = { 'list' => '1,2,3', 'list_not_integer' => 'a,b,c', 'other' => 'x' }
    schema = {
      'properties' => {
        'list' => {
          'type' => 'array',
          'items' => { 'type' => 'integer' }
        },
        'list_not_integer' => {
          'type' => 'array',
          'items' => { 'type' => 'string' }
        },
        'other' => {
          'type' => 'string'
        }
      }
    }
    assert(JSONSchemer.schema(
      schema,
      before_property_validation: [parse_array]
    ).valid?(data))
    assert_equal({'list' => [1, 2, 3], 'list_not_integer' => %w[a b c], 'other' => 'x'}, data)
  end

  def test_use_before_validation_hook_to_act_on_parent_schema
    skip_read_only = proc do |data, property, property_schema, schema|
      next unless property_schema['readOnly']
      schema['required'].delete(property)
      if data.key?(property) && property_schema.is_a?(Hash)
        data.delete(property)
      end
    end
    schema = {
      'required' => ['read_only_existing'],
      'properties' => {
        'read_only_existing' => {
          'type' => 'integer',
          'readOnly' => true
        },
        'not_read_only' => {
          'type' => 'string'
        },
        'read_only_missing' => {
          'type' => 'string',
          'readOnly' => true
        }
      }
    }
    schemer = JSONSchemer.schema(
      schema,
      before_property_validation: [skip_read_only]
    )
    data = { 'read_only_existing' => 1, 'not_read_only' => 'x' }
    assert_empty(schemer.validate(data).to_a)
    assert_equal({ 'not_read_only' => 'x' }, data)

    data = {}
    assert_empty(schemer.validate(data).to_a)
    assert_equal({}, data)
  end

  def test_it_accepts_a_single_before_validation_hook_to_modify_data
    parse_array = proc do |data, property, property_schema, _|
      if data.key?(property) && property_schema.is_a?(Hash) && property_schema['type'] == 'array'
        data[property] = data[property].split(',')
        data[property].map!(&:to_i) if property_schema['items']['type'] == 'integer'
      end
    end
    data = { 'list' => '1,2,3', 'list_not_integer' => 'a,b,c', 'other' => 'x' }
    schema = {
      'properties' => {
        'list' => {
          'type' => 'array',
          'items' => { 'type' => 'integer' }
        },
        'list_not_integer' => {
          'type' => 'array',
          'items' => { 'type' => 'string' }
        },
        'other' => {
          'type' => 'string'
        }
      }
    }
    assert(JSONSchemer.schema(
      schema,
      before_property_validation: parse_array
    ).valid?(data))
    assert_equal({'list' => [1, 2, 3], 'list_not_integer' => %w[a b c], 'other' => 'x'}, data)
  end

  def test_it_calls_after_validation_hooks_to_modify_data
    convert_date = proc do |data, property, property_schema, _|
      if data[property] && property_schema.is_a?(Hash) && property_schema['format'] == 'date'
        data[property] = Date.iso8601(data[property])
      end
    end
    schema = {
      'properties' => {
        'start_date' => {
          'type' => 'string',
          'format' => 'date'
        },
        'email' => {
          'format' => 'email'
        }
      }
    }
    validator= JSONSchemer.schema(
      schema,
      after_property_validation: [convert_date]
    )
    data = { 'start_date' => '2020-09-03', 'email' => 'example@example.com' }
    assert(validator.valid?(data))
    assert_equal({'start_date' => Date.new(2020, 9, 3), 'email' => 'example@example.com'}, data)
  end

  def test_it_accepts_a_single_proc_as_after_validation_hook
    convert_date = proc do |data, property, property_schema|
      if data[property] && property_schema.is_a?(Hash) && property_schema['format'] == 'date'
        data[property] = Date.iso8601(data[property])
      end
    end
    schema = {
      'properties' => {
        'start_date' => {
          'type' => 'string',
          'format' => 'date'
        },
        'email' => {
          'format' => 'email'
        }
      }
    }
    validator= JSONSchemer.schema(
      schema,
      after_property_validation: convert_date
    )
    data = { 'start_date' => '2020-09-03', 'email' => 'example@example.com' }
    assert(validator.valid?(data))
    assert_equal({'start_date' => Date.new(2020, 9, 3), 'email' => 'example@example.com' }, data)
  end

  def test_it_does_not_modify_passed_hooks_array
    schema = {
      'properties' => {
        'list' => {
          'type' => 'array',
          'items' => { 'type' => 'string' }
        }
      }
    }
    data = [{ 'name' => 'Bob' }]
    assert(JSONSchemer.schema(
      schema,
      before_property_validation: [proc {}].freeze,
      after_property_validation: [proc {}].freeze,
      insert_property_defaults: true
    ).valid?(data))
  end

  def test_after_property_validation_hook_does_not_corrupt_instance_across_oneOf_subschemas
    convert_date = proc do |data, property, property_schema, _|
      if data.key?(property) && property_schema.is_a?(Hash) && property_schema['format'] == 'date'
        data[property] = Date.iso8601(data[property])
      end
    end

    schema = {
      'oneOf' => [
        {
          'required' => ['required_field'],
          'properties' => {
            'start_date' => { 'type' => 'string', 'format' => 'date' },
            'required_field' => { 'type' => 'string' }
          }
        },
        {
          'properties' => {
            'start_date' => { 'type' => 'string' }
          }
        }
      ]
    }

    data = { 'start_date' => '2020-09-03' }
    assert(JSONSchemer.schema(schema, after_property_validation: [convert_date]).valid?(data))
    assert_equal('2020-09-03', data['start_date'])
  end

  def test_after_property_validation_hook_does_not_corrupt_instance_across_anyOf_subschemas
    convert_date = proc do |data, property, property_schema, _|
      if data.key?(property) && property_schema.is_a?(Hash) && property_schema['format'] == 'date'
        data[property] = Date.iso8601(data[property])
      end
    end

    schema = {
      'anyOf' => [
        {
          'required' => ['required_field'],
          'properties' => {
            'start_date' => { 'type' => 'string', 'format' => 'date' },
            'required_field' => { 'type' => 'string' }
          }
        },
        {
          'properties' => {
            'start_date' => { 'type' => 'string' }
          }
        }
      ]
    }

    data = { 'start_date' => '2020-09-03' }
    assert(JSONSchemer.schema(schema, after_property_validation: [convert_date]).valid?(data))
    assert_equal('2020-09-03', data['start_date'])
  end

  def test_after_property_validation_hook_applies_changes_from_matching_oneOf_subschema
    convert_date = proc do |data, property, property_schema, _|
      if data.key?(property) && property_schema.is_a?(Hash) && property_schema['format'] == 'date'
        data[property] = Date.iso8601(data[property])
      end
    end

    schema = {
      'oneOf' => [
        {
          'properties' => {
            'start_date' => { 'type' => 'string', 'format' => 'date' }
          }
        },
        {
          'required' => ['required_field'],
          'properties' => {
            'start_date' => { 'type' => 'string' },
            'required_field' => { 'type' => 'string' }
          }
        }
      ]
    }

    data = { 'start_date' => '2020-09-03' }
    assert(JSONSchemer.schema(schema, after_property_validation: [convert_date]).valid?(data))
    assert_equal(Date.new(2020, 9, 3), data['start_date'])
  end

  def test_stringified_keys_hooks_receive_caller_data
    seen = []
    hook = proc { |data, property, _property_schema, _parent| seen << data if property == 'a' }
    schema = JSONSchemer.schema(
      { 'properties' => { 'nested' => { 'properties' => { 'a' => { 'type' => 'integer' } } } } },
      before_property_validation: [hook],
      after_property_validation: [hook],
      stringified_keys: true
    )

    nested = { 'a' => 1 }
    data = { 'nested' => nested }
    assert(schema.valid?(data))
    assert_equal(2, seen.size)
    seen.each { |hook_data| assert_same(nested, hook_data) }
    assert_same(nested, data.fetch('nested'))
  end

  def test_stringified_keys_hook_changes_are_validated
    to_integer = proc do |data, property, property_schema, _parent|
      data[property] = Integer(data[property]) if data[property].is_a?(String) && property_schema['type'] == 'integer'
    end
    schema = JSONSchemer.schema(
      { 'properties' => { 'a' => { 'type' => 'integer' } } },
      before_property_validation: [to_integer],
      stringified_keys: true
    )

    data = { 'a' => '1' }
    assert(schema.valid?(data))
    assert_equal({ 'a' => 1 }, data)
  end

  def test_stringified_keys_after_property_validation_hook_does_not_corrupt_instance_across_oneOf_subschemas
    convert_date = proc do |data, property, property_schema, _|
      if data.key?(property) && property_schema.is_a?(Hash) && property_schema['format'] == 'date'
        data[property] = Date.iso8601(data[property])
      end
    end

    schema = {
      'oneOf' => [
        {
          'required' => ['required_field'],
          'properties' => {
            'start_date' => { 'type' => 'string', 'format' => 'date' },
            'required_field' => { 'type' => 'string' }
          }
        },
        {
          'properties' => {
            'start_date' => { 'type' => 'string' }
          }
        }
      ]
    }

    data = { 'start_date' => '2020-09-03' }
    assert(JSONSchemer.schema(schema, after_property_validation: [convert_date], stringified_keys: true).valid?(data))
    assert_equal('2020-09-03', data['start_date'])
  end

  CONVERT_DATE = proc do |data, property, property_schema, _parent|
    if data[property].is_a?(String) && property_schema.is_a?(Hash) && property_schema['format'] == 'date'
      data[property] = Date.iso8601(data[property])
    end
  end

  SET_DEFAULT = proc do |data, property, property_schema, _parent|
    data[property] = property_schema['default'] if !data.key?(property) && property_schema.is_a?(Hash) && property_schema.key?('default')
  end

  def assert_isolated(schema, data, expected_valid, expected_data, **options)
    [false, true].each do |stringified_keys|
      instance = Marshal.load(Marshal.dump(data))
      schemer = JSONSchemer.schema(schema, stringified_keys: stringified_keys, **options)
      assert_equal(expected_valid, schemer.valid?(instance), "valid? (stringified_keys: #{stringified_keys})")
      assert_equal(expected_data, instance, "data (stringified_keys: #{stringified_keys})")
      instance = Marshal.load(Marshal.dump(data))
      assert_equal(expected_valid, schemer.validate(instance, output_format: 'basic').fetch('valid'), "validate (stringified_keys: #{stringified_keys})")
      assert_equal(expected_data, instance, "validate data (stringified_keys: #{stringified_keys})")
    end
  end

  def test_oneOf_subschemas_do_not_see_changes_from_other_subschemas
    schema = {
      'oneOf' => [
        { 'properties' => { 'start_date' => { 'type' => 'string', 'format' => 'date' } } },
        { 'properties' => { 'start_date' => { 'type' => 'string' } } }
      ]
    }
    assert_isolated(schema, { 'start_date' => '2020-09-03' }, false, { 'start_date' => '2020-09-03' }, after_property_validation: [CONVERT_DATE])
  end

  def test_anyOf_keeps_changes_from_first_valid_subschema
    schema = {
      'anyOf' => [
        { 'required' => ['missing'], 'properties' => { 'a' => { 'default' => 'first' } } },
        { 'properties' => { 'a' => { 'default' => 'second' }, 'start_date' => { 'format' => 'date' } } },
        { 'properties' => { 'a' => { 'default' => 'third' } } }
      ]
    }
    assert_isolated(
      schema,
      { 'start_date' => '2020-09-03' },
      true,
      { 'a' => 'second', 'start_date' => Date.new(2020, 9, 3) },
      before_property_validation: [SET_DEFAULT],
      after_property_validation: [CONVERT_DATE]
    )
  end

  def test_oneOf_discards_all_changes_when_invalid
    schema = {
      'oneOf' => [
        { 'properties' => { 'a' => { 'default' => 1 } } },
        { 'properties' => { 'b' => { 'default' => 2 } } }
      ]
    }
    assert_isolated(schema, {}, false, {}, before_property_validation: [SET_DEFAULT])
  end

  def test_not_discards_changes
    schema = { 'not' => { 'properties' => { 'a' => { 'default' => 1 } }, 'required' => ['missing'] } }
    assert_isolated(schema, {}, true, {}, before_property_validation: [SET_DEFAULT])

    schema = { 'not' => { 'properties' => { 'a' => { 'default' => 1 } } } }
    assert_isolated(schema, {}, false, {}, before_property_validation: [SET_DEFAULT])
  end

  def test_if_keeps_changes_only_when_matching
    schema = {
      'if' => { 'properties' => { 'a' => { 'default' => 1 } }, 'required' => ['b'] },
      'then' => { 'properties' => { 'c' => { 'default' => 3 } } },
      'else' => { 'properties' => { 'd' => { 'default' => 4 } } }
    }
    assert_isolated(schema, {}, true, { 'd' => 4 }, before_property_validation: [SET_DEFAULT])
    assert_isolated(schema, { 'b' => 2 }, true, { 'a' => 1, 'b' => 2, 'c' => 3 }, before_property_validation: [SET_DEFAULT])
  end

  def test_contains_keeps_changes_only_for_matching_items
    schema = { 'contains' => { 'properties' => { 'a' => { 'default' => 1 } }, 'required' => ['b'] } }
    assert_isolated(schema, [{}, { 'b' => 2 }], true, [{}, { 'a' => 1, 'b' => 2 }], before_property_validation: [SET_DEFAULT])
  end

  def test_nested_changes_are_discarded_with_failed_subschema
    schema = {
      'anyOf' => [
        {
          'properties' => {
            'nested' => {
              'allOf' => [
                { 'properties' => { 'a' => { 'default' => 1 } } },
                { 'anyOf' => [{ 'properties' => { 'b' => { 'default' => 2 } } }] }
              ]
            },
            'start_date' => { 'format' => 'date' }
          },
          'required' => ['missing']
        },
        { 'properties' => { 'nested' => { 'properties' => { 'c' => { 'default' => 3 } } } } }
      ]
    }
    assert_isolated(
      schema,
      { 'nested' => {}, 'start_date' => '2020-09-03' },
      true,
      { 'nested' => { 'c' => 3 }, 'start_date' => '2020-09-03' },
      before_property_validation: [SET_DEFAULT],
      after_property_validation: [CONVERT_DATE]
    )
  end

  def test_kept_nested_changes_are_discarded_with_failed_outer_subschema
    schema = {
      'anyOf' => [
        {
          'oneOf' => [{ 'properties' => { 'nested' => { 'properties' => { 'a' => { 'default' => 1 } } } } }],
          'required' => ['missing']
        },
        { 'properties' => { 'b' => { 'default' => 2 } } }
      ]
    }
    assert_isolated(schema, { 'nested' => {} }, true, { 'nested' => {}, 'b' => 2 }, before_property_validation: [SET_DEFAULT])
  end

  def test_isolation_with_symbol_keys
    schema = {
      'properties' => {
        'item' => {
          'oneOf' => [
            { 'properties' => { 'start_date' => { 'format' => 'date' } }, 'required' => ['missing'] },
            { 'properties' => { 'start_date' => { 'type' => 'string' } } }
          ]
        }
      }
    }
    data = { :item => { :start_date => '2020-09-03' } }
    assert(JSONSchemer.schema(schema, after_property_validation: [CONVERT_DATE]).valid?(data))
    assert_equal({ :item => { :start_date => '2020-09-03' } }, data)
  end

  def test_before_property_validation_runs_before_other_keywords
    schema = {
      'properties' => { 'kind' => { 'default' => 'a' } },
      'oneOf' => [
        { 'properties' => { 'kind' => { 'const' => 'a' } }, 'required' => ['kind'] },
        { 'properties' => { 'kind' => { 'const' => 'b' } }, 'required' => ['kind'] }
      ],
      'if' => { 'required' => ['kind'] },
      'then' => { 'properties' => { 'checked' => { 'default' => true } } }
    }
    assert_isolated(schema, {}, true, { 'kind' => 'a', 'checked' => true }, before_property_validation: [JSONSchemer::Schema::INSERT_PROPERTY_DEFAULT])
    assert_isolated(schema, { 'kind' => 'b' }, true, { 'kind' => 'b', 'checked' => true }, before_property_validation: [JSONSchemer::Schema::INSERT_PROPERTY_DEFAULT])
  end

  def test_before_property_validation_values_are_seen_by_conditionals
    schema = {
      'properties' => { 'kind' => { 'enum' => ['person', 'company'], 'default' => 'person' }, 'name' => {}, 'inn' => {} },
      'if' => { 'properties' => { 'kind' => { 'const' => 'company' } } },
      'then' => { 'required' => ['inn'] },
      'else' => { 'required' => ['name'] }
    }
    # `if` must see the inserted default, otherwise it passes because `kind` is missing and `then` is applied
    assert_isolated(schema, { 'inn' => '1' }, false, { 'inn' => '1', 'kind' => 'person' }, before_property_validation: [JSONSchemer::Schema::INSERT_PROPERTY_DEFAULT])
    assert_isolated(schema, { 'name' => 'x' }, true, { 'name' => 'x', 'kind' => 'person' }, before_property_validation: [JSONSchemer::Schema::INSERT_PROPERTY_DEFAULT])
  end

  def test_before_property_validation_values_are_seen_by_dependent_schemas
    compute = proc { |data, property, property_schema, _parent| data[property] = 1 if property_schema.is_a?(Hash) && property_schema['x-computed'] }
    schema = {
      'properties' => { 'total' => { 'x-computed' => true } },
      'dependentSchemas' => { 'total' => { 'required' => ['currency'] } }
    }
    assert_isolated(schema, {}, false, { 'total' => 1 }, before_property_validation: [compute])
    assert_isolated(schema, { 'currency' => 'EUR' }, true, { 'currency' => 'EUR', 'total' => 1 }, before_property_validation: [compute])
  end

  def test_after_property_validation_changes_are_not_validated
    data = { 'start_date' => '2020-09-03', 'nested' => { 'end_date' => '2020-09-04' } }
    converted = { 'start_date' => Date.new(2020, 9, 3), 'nested' => { 'end_date' => Date.new(2020, 9, 4) } }
    date = { 'type' => 'string', 'format' => 'date' }
    schemas = [
      { 'properties' => { 'start_date' => date, 'nested' => { 'properties' => { 'end_date' => date } } }, 'patternProperties' => { '_date$' => { 'type' => 'string' } } },
      { 'properties' => { 'start_date' => date, 'nested' => { 'properties' => { 'end_date' => date } } }, 'enum' => [data] },
      { 'allOf' => [{ 'properties' => { 'start_date' => date, 'nested' => { 'properties' => { 'end_date' => date } } } }, { 'properties' => { 'start_date' => { 'type' => 'string' } } }] },
      { 'properties' => { 'nested' => { 'properties' => { 'end_date' => date } } }, 'required' => ['nested'], 'const' => { 'start_date' => '2020-09-03', 'nested' => { 'end_date' => '2020-09-04' } } }
    ]
    schemas.each do |schema|
      expected = schema.key?('const') ? converted.merge('start_date' => '2020-09-03') : converted
      assert_isolated(schema, data, true, expected, after_property_validation: [CONVERT_DATE])
    end
  end

  def test_after_property_validation_runs_once_after_validation_for_applicable_subschemas
    calls = []
    hook = proc { |data, property, _property_schema, _parent| calls << [property, data.fetch(property, nil)] if data.key?(property) }
    schema = {
      'properties' => { 'outer' => { 'properties' => { 'inner' => {} } } },
      'oneOf' => [
        { 'properties' => { 'kind' => { 'const' => 'a' } }, 'required' => ['kind'] },
        { 'properties' => { 'kind' => { 'const' => 'b' } }, 'required' => ['kind'] }
      ],
      'not' => { 'properties' => { 'missing' => {} }, 'required' => ['missing'] },
      'if' => { 'properties' => { 'kind' => {} }, 'required' => ['missing'] },
      'contains' => true
    }

    [{}, { insert_property_defaults: true }].each do |options|
      calls.clear
      data = { 'kind' => 'b', 'outer' => { 'inner' => 1 } }
      assert(JSONSchemer.schema(schema, after_property_validation: [hook], **options).valid?(data))
      # in validation order (`oneOf` before `properties`, nested objects before their parents), only the valid `oneOf`
      # subschema, nothing from `not` and the failed `if`
      assert_equal([['kind', 'b'], ['inner', 1], ['outer', { 'inner' => 1 }]], calls)
    end
  end

  def test_hooks_receive_instance_location_and_subschema
    calls = []
    hook = proc do |data, property, property_schema, parent_schema, instance_location, subschema|
      calls << [property, instance_location, subschema.schema_pointer, subschema.value.equal?(property_schema), parent_schema.key?('properties'), data.key?(property)]
    end
    schemer = JSONSchemer.schema(
      {
        'properties' => { 'items' => { 'type' => 'array', 'items' => { '$ref' => '#/$defs/item' } } },
        '$defs' => { 'item' => { 'properties' => { 'total' => { '$ref' => '#/$defs/total' } } }, 'total' => { 'x-expression' => 'a + b' } }
      },
      before_property_validation: [hook],
      after_property_validation: [hook]
    )

    assert(schemer.valid?({ 'items' => [{ 'total' => 1 }, {}] }))
    assert_equal(
      [
        ['items', '', '/properties/items', true, true, true],
        ['total', '/items/0', '/$defs/item/properties/total', true, true, true],
        ['total', '/items/1', '/$defs/item/properties/total', true, true, false],
        ['total', '/items/0', '/$defs/item/properties/total', true, true, true],
        ['total', '/items/1', '/$defs/item/properties/total', true, true, false],
        ['items', '', '/properties/items', true, true, true]
      ],
      calls
    )

    # the subschema resolves references, eg to find an expression behind `$ref`
    expressions = []
    collect = proc do |_data, _property, _property_schema, _parent_schema, _instance_location, subschema|
      expressions << subschema.parsed['$ref']&.ref_schema&.value&.fetch('x-expression')
    end
    JSONSchemer.schema(schemer.value, before_property_validation: [collect]).valid?({ 'items' => [{}] })
    assert_equal([nil, 'a + b'], expressions)
  end

  def test_before_property_validation_runs_once
    calls = Hash.new(0)
    counter = proc { |_data, property, _property_schema, _parent| calls[property] += 1 }
    schema = { 'properties' => { 'a' => { 'default' => 1 }, 'b' => { 'type' => 'integer' } }, 'required' => ['a'] }

    data = {}
    assert(JSONSchemer.schema(schema, before_property_validation: [JSONSchemer::Schema::INSERT_PROPERTY_DEFAULT, counter]).valid?(data))
    assert_equal({ 'a' => 1 }, data)
    assert_equal({ 'a' => 1, 'b' => 1 }, calls)
  end

  def test_insert_property_default_hook
    default = { 'nested' => { 'list' => ['x'] } }
    schema = {
      'properties' => {
        'a' => { 'type' => 'object', 'default' => default },
        'b' => { 'default' => 'b' },
        'c' => { 'default' => nil },
        'd' => { 'default' => 'd' },
        'e' => true
      },
      'required' => ['a', 'b', 'c', 'd']
    }

    data = { 'd' => 'existing' }
    assert(JSONSchemer.schema(schema, before_property_validation: [JSONSchemer::Schema::INSERT_PROPERTY_DEFAULT]).valid?(data))
    assert_equal({ 'a' => default, 'b' => 'b', 'c' => nil, 'd' => 'existing' }, data)

    data.fetch('a').fetch('nested').fetch('list') << 'y'
    data.fetch('b') << 'b'
    assert_equal({ 'nested' => { 'list' => ['x'] } }, default)
    assert_equal('b', schema.dig('properties', 'b', 'default'))

    data = { :b => 'existing' }
    assert(JSONSchemer.schema(schema, before_property_validation: [JSONSchemer::Schema::INSERT_PROPERTY_DEFAULT]).valid?(data))
    refute(data.key?('b'))
    assert_equal('existing', data.fetch(:b))
  end

  def test_insert_property_default_hook_called_directly
    wrapper = proc do |data, property, property_schema, parent|
      JSONSchemer::Schema::INSERT_PROPERTY_DEFAULT.call(data, property, property_schema, parent)
    end
    schema = {
      'properties' => {
        'a' => { 'default' => { 'x' => ['y'] } },
        'b' => { 'default' => 'b' },
        'c' => { '$ref' => '#/$defs/c' },
        'd' => true
      },
      '$defs' => { 'c' => { 'default' => 'c' } }
    }

    data = { :b => 'existing' }
    assert(JSONSchemer.schema(schema, before_property_validation: [wrapper]).valid?(data))
    assert_equal({ :b => 'existing', 'a' => { 'x' => ['y'] } }, data)
    refute_same(schema.dig('properties', 'a', 'default'), data.fetch('a'))
    refute_same(schema.dig('properties', 'a', 'default', 'x'), data.fetch('a').fetch('x'))
  end

  def test_hooks_with_content_schema
    seen = []
    hook = proc { |data, property, _property_schema, _parent| seen << data.dup if property == 'a' }
    schema = {
      'contentMediaType' => 'application/json',
      'contentSchema' => { 'properties' => { 'a' => { 'type' => 'integer', 'default' => 1 } }, 'required' => ['a'] }
    }
    [false, true].each do |stringified_keys|
      seen.clear
      schemer = JSONSchemer.schema(schema, before_property_validation: [JSONSchemer::Schema::INSERT_PROPERTY_DEFAULT, hook], stringified_keys: stringified_keys)
      data = '{}'
      assert(schemer.valid?(data))
      assert_equal('{}', data)
      assert_equal([{ 'a' => 1 }], seen)
    end
  end

  def test_insert_property_default_hook_with_computed_values
    compute = proc do |data, property, property_schema, _parent|
      if property_schema.is_a?(Hash) && property_schema.key?('x-sum')
        data[property] = property_schema.fetch('x-sum').sum { |other| data.fetch(other) }
      end
    end
    schema = {
      'properties' => {
        'a' => { 'type' => 'integer' },
        'b' => { 'type' => 'integer', 'default' => 2 },
        'total' => { 'type' => 'integer', 'maximum' => 10, 'x-sum' => ['a', 'b'] }
      },
      'required' => ['a', 'total']
    }

    assert_isolated(schema, { 'a' => 1 }, true, { 'a' => 1, 'b' => 2, 'total' => 3 }, before_property_validation: [JSONSchemer::Schema::INSERT_PROPERTY_DEFAULT, compute])
    assert_isolated(schema, { 'a' => 1, 'b' => 20 }, false, { 'a' => 1, 'b' => 20, 'total' => 21 }, before_property_validation: [JSONSchemer::Schema::INSERT_PROPERTY_DEFAULT, compute])
  end

  def test_insert_property_default_hook_skips_failed_subschemas
    schema = {
      'type' => 'object',
      'properties' => {
        'list' => {
          'type' => 'array',
          'items' => {
            'oneOf' => [
              { 'properties' => { 'kind' => { 'const' => 'a' }, 'a' => { 'default' => 1 } }, 'required' => ['kind'] },
              { 'properties' => { 'kind' => { 'const' => 'b' }, 'b' => { 'default' => 2 } }, 'required' => ['kind'] }
            ]
          }
        }
      }
    }
    assert_isolated(
      schema,
      { 'list' => [{ 'kind' => 'a' }, { 'kind' => 'b' }] },
      true,
      { 'list' => [{ 'kind' => 'a', 'a' => 1 }, { 'kind' => 'b', 'b' => 2 }] },
      before_property_validation: [JSONSchemer::Schema::INSERT_PROPERTY_DEFAULT]
    )
  end

end
