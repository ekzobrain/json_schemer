require 'test_helper'

class HooksTest < Minitest::Test
  def test_it_inserts_defaults
    schema = {
      'required' => ['a', 'c', 'd'],
      'properties' => {
        'a' => { 'default' => 1 },
        'b' => { 'default' => 2 },
        'c' => {
          'required' => ['x'],
          'properties' => {
            'x' => { 'default' => 3 },
            'y' => { 'default' => 4 }
          }
        },
        'd' => {
          'required' => ['x'],
          'default' => {
            'x' => {
              'y' => {
                'z' => 1
              }
            }
          },
          'properties' => {
            'x' => {
              'required' => ['y'],
              'properties' => {
                'y' => {
                  'required' => ['z'],
                  'properties' => {
                    'z' => { 'type' => 'integer' }
                  }
                }
              }
            }
          }
        }
      }
    }
    data = {
      'a' => 10,
      'c' => {
        'x' => 30
      }
    }
    refute(JSONSchemer.schema(schema).valid?(data))
    assert(JSONSchemer.schema(schema, insert_property_defaults: true).valid?(data))
    assert_equal(
      {
        'a' => 10,
        'b' => 2,
        'c' => {
          'x' => 30,
          'y' => 4
        },
        'd' => {
          'x' => {
            'y' => {
              'z' => 1
            }
          }
        }
      },
      data
    )
  end

  def test_it_inserts_defaults_in_symbol_keys
    schemer = JSONSchemer.schema(
      {
        'properties' => {
          'a' => {
            'properties' => {
              'b' => {
                'properties' => {
                  'c' => {
                    'default' => 'x'
                  }
                }
              }
            }
          }
        }
      },
      insert_property_defaults: true
    )
    instance = { 'a' => { 'b' => {} } }
    schemer.validate(instance)
    assert_equal('x', instance.dig('a', 'b', 'c'))
    instance = { :a => { 'b' => {} } }
    schemer.validate(instance)
    assert_equal('x', instance.dig(:a, 'b', 'c'))
    instance = { 'a' => { :b => {} } }
    schemer.validate(instance)
    assert_equal('x', instance.dig('a', :b, 'c'))
    instance = { :a => { :b => {} } }
    schemer.validate(instance)
    assert_equal('x', instance.dig(:a, :b, 'c'))
  end

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

  def test_it_does_not_fail_using_insert_defaults_when_no_properties_are_defined_by_schema
    schema = {
      '$comment' => 'Mostly empty schema'
    }
    data = {
      'a' => 1
    }
    assert(JSONSchemer.schema(schema, insert_property_defaults: true).valid?(data))
    assert_equal({ 'a' => 1 }, data)
  end

  def test_it_does_not_fail_using_insert_defaults_when_properties_contains_a_boolean_defined_property
    schema = {
      'properties' => {
        'a' => true
      }
    }
    data = {
      'a' => 1
    }
    assert(JSONSchemer.schema(schema, insert_property_defaults: true).valid?(data))
    assert_equal({ 'a' => 1 }, data)
  end

  def test_it_does_not_fail_using_insert_defaults_when_properties_contains_a_boolean_defined_property_that_does_not_exist
    schema = {
      'properties' => {
        'b' => true
      }
    }
    data = {
      'a' => 1
    }
    assert(JSONSchemer.schema(schema, insert_property_defaults: true).valid?(data))
    assert_equal({ 'a' => 1 }, data)
  end

  def test_it_inserts_singular_unique_defaults_in_conditional_subschemas
    c_schema = {
      'const' => 3
    }
    properties = {
      'a' => {
        'const' => 1
      },
      'b' => {
        'const' => 2,
        'default' => 2
      },
      'c' => c_schema
    }
    subschema = {
      'properties' => properties
    }
    subschema1 = subschema.merge('properties' => properties.merge('c' => c_schema.merge('default' => 1)))
    subschema2 = subschema.merge('properties' => properties.merge('c' => c_schema.merge('default' => 2)))
    subschema3 = subschema.merge('properties' => properties.merge('c' => c_schema.merge('default' => 3)))
    subschema4 = subschema.merge('properties' => properties.merge('c' => c_schema.merge('default' => 4)))
    schema = {
      'allOf' => [subschema1],
      'anyOf' => [subschema2],
      'oneOf' => [subschema3],
      'if' => subschema4
    }
    data = {
      'a' => 1
    }
    assert(JSONSchemer.schema(schema, insert_property_defaults: true).valid?(data))
    assert_equal({ 'a' => 1, 'b' => 2 }, data)
    refute(JSONSchemer.schema(schema.merge('not' => subschema), insert_property_defaults: true).valid?(data))
    assert_equal({ 'a' => 1, 'b' => 2 }, data)
  end

  def test_it_inserts_only_default_in_conditional_subschemas
    top_level_schema = JSONSchemer.schema(
      {
        'required' => ['field', 'default_field'],
        'properties' => {
          'field' => { 'type' => 'string', 'const' => 'a' },
          'default_field' => { 'enum' => ['f1', 'f2'], 'default' => 'f1' },
        }
      },
      :insert_property_defaults => true
    )

    one_of_schema = JSONSchemer.schema(
      {
        'oneOf' => [
          { '$ref' => '#/definitions/a' }
        ],
        'required' => ['field', 'default_field'],
        'definitions' => {
          'a' => {
            'properties' => {
              'field' => { 'type' => 'string', 'const' => 'a' },
              'default_field' => { 'enum' => ['f1', 'f2'], 'default' => 'f1' },
            }
          }
        }
      },
      :insert_property_defaults => true
    )

    data1 = { 'field' => 'a' }
    data2 = { 'field' => 'a' }

    assert(top_level_schema.valid?(data1))
    assert(one_of_schema.valid?(data2))

    assert_equal({ 'field' => 'a', 'default_field' => 'f1' }, data1)
    assert_equal({ 'field' => 'a', 'default_field' => 'f1' }, data2)
  end

  def test_it_does_not_insert_defaults_in_not_subschemas
    schema = {
      'properties' => {
        'a' => {
          'default' => 1
        }
      }
    }

    data = { 'b' => 2 }
    assert(JSONSchemer.schema(schema, :insert_property_defaults => true).valid?(data))
    assert_equal({ 'b' => 2, 'a' => 1 }, data)

    data = { 'b' => 2 }
    refute(JSONSchemer.schema({ 'not' => schema }, :insert_property_defaults => true).valid?(data))
    assert_equal({ 'b' => 2 }, data)
  end

  def test_it_inserts_default_for_successful_branch
    schema = {
      'oneOf' => [
        {
          'type' => 'object',
          'properties' => {
            'foo' => { 'enum' => ['a'] },
            'bar' => { 'enum' => ['a'], 'default' => 'a' }
          }
        },
        {
          'type' => 'object',
          'properties' => {
            'foo' => { 'enum' => ['b'] },
            'bar' => { 'enum' => ['b'], 'default' => 'b' }
          }
        },
      ]
    }

    data = { 'foo' => 'a' }
    assert(JSONSchemer.schema(schema).valid?(data))
    assert_equal({ 'foo' => 'a' }, data)

    data = { 'foo' => 'b' }
    assert(JSONSchemer.schema(schema).valid?(data))
    assert_equal({ 'foo' => 'b' }, data)

    data = { 'foo' => 'a' }
    assert(JSONSchemer.schema(schema, :insert_property_defaults => true).valid?(data))
    assert_equal({ 'foo' => 'a', 'bar' => 'a' }, data)

    data = { 'foo' => 'b' }
    assert(JSONSchemer.schema(schema, :insert_property_defaults => true).valid?(data))
    assert_equal({ 'foo' => 'b', 'bar' => 'b' }, data)
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

  def test_it_calls_before_validation_hooks_and_still_inserts_defaults
    replace_fake_with_peter = proc do |data, property, property_schema, _|
      data[property] = 'Peter' if property == 'name' && data[property] == 'fake'
    end
    data = [{ }, { 'name' => 'Bob' }]
    assert(JSONSchemer.schema(
      {
        'type' => 'array',
        'items' => {
          'type' => 'object',
          'properties' => {
            'name' => {
              'type' => 'string',
              'default' => 'fake'
            }
          }
        }
      },
      insert_property_defaults: true,
      before_property_validation: [replace_fake_with_peter]
    ).valid?(data))
    assert_equal([{ 'name' => 'Peter' }, { 'name' => 'Bob' }], data)
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

  def test_insert_property_defaults_refs
    schema = {
      'properties' => {
        'inline' => {
          'default' => 'a'
        },
        'ref-inline' => {
          '$ref' => '#/$defs/default-b'
        },
        'ref-inherit' => {
          '$ref' => '#/$defs/inherit-default-b'
        },
        'ref-inline-override' => {
          '$ref' => '#/$defs/default-b',
          'default' => 'c'
        },
        'ref-inherit-override' => {
          '$ref' => '#/$defs/inherit-default-b',
          'default' => 'd'
        },
        'ref-override' => {
          '$ref' => '#/$defs/override-default-e'
        }
      },
      '$defs' => {
        'default-b' => {
          'default' => 'b'
        },
        'inherit-default-b' => {
          '$ref' => '#/$defs/default-b'
        },
        'override-default-e' => {
          '$ref' => '#/$defs/default-b',
          'default' => 'e'
        }
      }
    }
    data = {}
    assert(JSONSchemer.schema(schema, insert_property_defaults: true).valid?(data))
    assert_equal('a', data.fetch('inline'))
    assert_equal('b', data.fetch('ref-inline'))
    assert_equal('b', data.fetch('ref-inherit'))
    assert_equal('c', data.fetch('ref-inline-override'))
    assert_equal('d', data.fetch('ref-inherit-override'))
    assert_equal('e', data.fetch('ref-override'))
  end

  def test_insert_property_defaults_dynamic_refs
    schema = {
      'properties' => {
        'dynamic-ref-inline' => {
          '$dynamicRef' => '#default-b'
        },
        'dynamic-ref-inline-override' => {
          '$dynamicRef' => '#default-b',
          'default' => 'c'
        },
        'dynamic-ref-and-ref' => {
          '$dynamicRef' => '#default-b',
          '$ref' => '#/$defs/default-a'
        }
      },
      '$defs' => {
        'default-a' => {
          'default' => 'a'
        },
        'foo' => {
          '$dynamicAnchor' => 'default-b',
          'default' => 'b'
        }
      }
    }
    data = {}
    assert(JSONSchemer.schema(schema, insert_property_defaults: true).valid?(data))
    assert_equal('b', data.fetch('dynamic-ref-inline'))
    assert_equal('c', data.fetch('dynamic-ref-inline-override'))
    assert_equal('a', data.fetch('dynamic-ref-and-ref'))
  end

  def test_insert_property_defaults_recursive_refs
    schema = {
      '$recursiveAnchor' => true,
      'default' => 'b',
      'properties' => {
        'recursive-ref-inline' => {
          '$recursiveRef' => '#'
        },
        'recursive-ref-inline-override' => {
          '$recursiveRef' => '#',
          'default' => 'c'
        },
        'recursive-ref-and-ref' => {
          '$recursiveRef' => '#',
          '$ref' => '#/$defs/default-a'
        }
      },
      '$defs' => {
        'default-a' => {
          'default' => 'a'
        }
      }
    }
    data = {}
    assert(JSONSchemer.schema(schema, meta_schema: JSONSchemer.draft201909, insert_property_defaults: true).valid?(data))
    assert_equal('b', data.fetch('recursive-ref-inline'))
    assert_equal('c', data.fetch('recursive-ref-inline-override'))
    assert_equal('a', data.fetch('recursive-ref-and-ref'))
  end

  def test_insert_property_defaults_non_ref_schema_keywords
    schema = {
      'properties' => {
        'x' => {
          '$anchor' => 'x', # parsed before `$ref`
          '$ref' => '#/$defs/y',
          'type' => 'string' # parsed after `$ref`
        }
      },
      '$defs' => {
        'y' => {
          'default' => 'z'
        }
      }
    }
    data = {}
    assert(JSONSchemer.schema(schema, insert_property_defaults: true).valid?(data))
    assert_equal('z', data.fetch('x'))
    refute(JSONSchemer.schema(schema, insert_property_defaults: true).valid?({ 'x' => 1 }))
  end

  def test_insert_property_defaults_ref_no_default
    schema = {
      'properties' => {
        'x' => {
          '$ref' => '#/$defs/y',
          '$dynamicRef' => '#z'
        }
      },
      '$defs' => {
        'y' => {
          'type' => 'string'
        },
        'foo' => {
          '$dynamicAnchor' => 'z',
          'default' => 'dynamic-ref'
        }
      }
    }
    data = {}
    assert(JSONSchemer.schema(schema, insert_property_defaults: true).valid?(data))
    assert_equal('dynamic-ref', data.fetch('x'))
    refute(JSONSchemer.schema(schema, insert_property_defaults: true).valid?({ 'x' => 1 }))
  end

  def test_insert_property_defaults_ref_depth_first
    schema = {
      'properties' => {
        'x' => {
          '$ref' => '#/$defs/ref1',
          '$dynamicRef' => '#dynamic-ref1'
        }
      },
      '$defs' => {
        'ref1' => {
          '$ref' => '#/$defs/ref2'
        },
        'ref2' => {
          '$ref' => '#/$defs/ref3'
        },
        'ref3' => {
          'default' => 'ref'
        },
        'foo' => {
          '$dynamicAnchor' => 'dynamic-ref1',
          '$dynamicRef' => '#dynamic-ref2'
        },
        'bar' => {
          '$dynamicAnchor' => 'dynamic-ref2',
          'default' => 'dynamic-ref'
        }
      }
    }
    data = {}
    assert(JSONSchemer.schema(schema, insert_property_defaults: true).valid?(data))
    assert_equal('ref', data.fetch('x'))
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

  def test_insert_property_defaults_compare_by_identity
    data = JSON.parse(%q({
      "fieldname": [
        { "aaaa": "item0", "bbbb": "val1", "cccc": true },
        { "aaaa": "item1", "cccc": true, "buggy": true, "dddd": 0 },
        { "aaaa": "item2", "cccc": true, "buggy": true, "dddd": 0 },
        { "aaaa": "item3", "buggy": true },
        { "aaaa": "item4", "cccc": true },
        { "aaaa": "item5", "cccc": true }
      ]
    }))
    schema = %q({
      "type": "object",
      "properties": {
        "fieldname": {
          "type": "array",
          "items": {
            "$ref": "#/$defs/Record"
          }
        }
      },
      "$defs": {
        "Enumerated": {
          "enum": [ "val1", "val2" ]
        },
        "Record": {
          "type": "object",
          "properties": {
            "aaaa": { "type": "string" },
            "cccc": { "type": "boolean", "default": false },
            "buggy": { "type": "boolean", "default": false },
            "bbbb": { "$ref": "#/$defs/Enumerated", "default": "val2" },
            "dddd": { "type": "number", "default": 0 },
            "eeee": { "type": "boolean", "default": false },
            "ffff": { "type": "boolean", "default": false }
          }
        }
      }
    })
    assert(JSONSchemer.schema(schema, insert_property_defaults: true).valid?(data))
    assert_equal('val2', data.dig('fieldname', 2, 'bbbb'))
    assert_equal(false, data.dig('fieldname', 3, 'cccc'))
    assert_equal(false, data.dig('fieldname', 4, 'buggy'))
    assert_equal(0, data.dig('fieldname', 0, 'dddd'))
    assert_equal(false, data.dig('fieldname', 1, 'eeee'))
    assert_equal(false, data.dig('fieldname', 5, 'ffff'))
  end
end
