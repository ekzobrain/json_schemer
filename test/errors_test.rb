require 'test_helper'

class ErrorsTest < Minitest::Test
  def test_x_error
    schema = {
      'oneOf' => [
        {
          'x-error' => 'properties a and b were provided, however only one or the other may be specified',
          'required' => ['a'],
          'not' => { 'required' => ['b'] }
        },
        {
          'x-error' => {
            'not' => <<~ERR
              instance: %{instance}
              instanceLocation: %{instanceLocation}
              formattedInstanceLocation: %{formattedInstanceLocation}
              keywordValue: %{keywordValue}
              keywordLocation: %{keywordLocation}
              absoluteKeywordLocation: %{absoluteKeywordLocation}
              details: %{details}
            ERR
          },
          'required' => ['b'],
          'not' => { 'required' => ['a'] }
        }
      ],
      'x-error' => {
        '*' => 'schema error',
        'oneOf' => 'oneOf error'
      }
    }
    data = {
      'a' => 'foo',
      'b' => 'bar'
    }
    error1, error2 = JSONSchemer.schema(schema).validate(data).map { |error| error.fetch('error') }

    assert_equal('properties a and b were provided, however only one or the other may be specified', error1)
    assert_equal(<<~ERR.gsub(/\s/,''), error2.gsub(/\s/,''))
      instance: {"a" => "foo", "b" => "bar"}
      instanceLocation:
      formattedInstanceLocation: root
      keywordValue: {"required" => ["a"]}
      keywordLocation: /oneOf/1/not
      absoluteKeywordLocation: json-schemer://schema#/oneOf/1/not
      details:
    ERR

    assert_equal('schema error', JSONSchemer.schema(schema).validate(data, :output_format => 'basic').fetch('error'))
    assert_equal('oneOf error', JSONSchemer.schema(schema).validate(data, :output_format => 'detailed').fetch('error'))

    assert_equal(true, JSONSchemer.schema(schema).validate(data, :output_format => 'basic').fetch('x-error'))
    assert_equal(true, JSONSchemer.schema(schema).validate(data, :output_format => 'detailed').fetch('x-error'))
    assert_equal([true, true], JSONSchemer.schema(schema).validate(data).map { |error| error.fetch('x-error') })

    refute(JSONSchemer.schema(schema).validate(data, :output_format => 'basic').key?('i18n'))
    refute(JSONSchemer.schema(schema).validate(data, :output_format => 'detailed').key?('i18n'))
    assert_equal([false, false], JSONSchemer.schema(schema).validate(data).map { |error| error.key?('i18n') })
  end

  def test_x_error_override
    schema = {
      'required' => ['a'],
      'minProperties' => 2
    }
    assert_equal(
      ['object at root is missing required properties: a', 'object size at root is less than: 2'].sort,
      JSONSchemer.schema(schema).validate({}).map { |error| error.fetch('error') }.sort
    )

    schema.merge!('x-error' => 'schema error')
    assert_equal(
      ['schema error', 'schema error'].sort,
      JSONSchemer.schema(schema).validate({}).map { |error| error.fetch('error') }.sort
    )
    assert_equal(
      'schema error',
      JSONSchemer.schema(schema).validate({}, :output_format => 'basic').fetch('error')
    )

    schema.merge!('x-error' => { 'required' => 'required error' })
    assert_equal(
      ['required error', 'object size at root is less than: 2'].sort,
      JSONSchemer.schema(schema).validate({}).map { |error| error.fetch('error') }.sort
    )

    schema.merge!('x-error' => { 'required' => 'required error', 'minProperties' => 'minProperties error' })
    assert_equal(
      ['required error', 'minProperties error'].sort,
      JSONSchemer.schema(schema).validate({}).map { |error| error.fetch('error') }.sort
    )

    schema.merge!('x-error' => { '*' => 'catchall', 'minProperties' => 'minProperties error' })
    assert_equal(
      ['catchall', 'minProperties error'].sort,
      JSONSchemer.schema(schema).validate({}).map { |error| error.fetch('error') }.sort
    )
    assert_equal(
      'catchall',
      JSONSchemer.schema(schema).validate({}, :output_format => 'basic').fetch('error')
    )

    schema.merge!('x-error' => { '^' => 'schema error', 'minProperties' => 'minProperties error' })
    assert_equal(
      ['object at root is missing required properties: a', 'minProperties error'].sort,
      JSONSchemer.schema(schema).validate({}).map { |error| error.fetch('error') }.sort
    )
    assert_equal(
      'schema error',
      JSONSchemer.schema(schema).validate({}, :output_format => 'basic').fetch('error')
    )

    schema.merge!('x-error' => { '^' => 'schema error', '*' => 'catchall' })
    assert_equal(
      ['catchall', 'catchall'].sort,
      JSONSchemer.schema(schema).validate({}).map { |error| error.fetch('error') }.sort
    )
    assert_equal(
      'schema error',
      JSONSchemer.schema(schema).validate({}, :output_format => 'basic').fetch('error')
    )
  end

  def test_x_error_precedence
    schema = {
      '$id' => 'https://example.com/schema',
      'required' => ['a']
    }
    x_error_schema = schema.merge(
      'x-error' => {
        'required' => 'x error'
      }
    )

    assert_equal('x error', JSONSchemer.schema(x_error_schema).validate({}).first.fetch('error'))
    assert_equal('object at root is missing required properties: a', JSONSchemer.schema(schema).validate({}).first.fetch('error'))

    i18n({ 'https://example.com/schema#/required' => 'i18n error' }) do
      assert_equal('x error', JSONSchemer.schema(x_error_schema).validate({}).first.fetch('error'))
      assert_equal('i18n error', JSONSchemer.schema(schema).validate({}).first.fetch('error'))
    end
  end

  def test_x_error_details_as_hash
    schema = {
      'properties' => {
        'yah' => {
          'type' => 'string'
        }
      },
      'required' => ['yah'],
      'x-error' => {
        'required' => 'missing %{details} %{details__missing_keys}'
      }
    }

    schemer = JSONSchemer.schema(schema)
    data = {}

    assert_match(optional_space_regexp('missing {"missing_keys"', '=>', '["yah"]} ["yah"]'), schemer.validate(data, :output_format => 'detailed').fetch('error'))
  end

  LIMITED = lambda do |instance, _schema, _instance_location|
    instance.is_a?(Integer) && instance > 10 ? 'is more than 10' : true
  end

  def test_custom_keyword_error
    schemer = JSONSchemer.schema(
      { 'type' => 'object', 'properties' => { 'a' => { 'type' => 'integer', 'limited' => true } } },
      :keywords => { 'limited' => LIMITED }
    )
    expected = {
      'valid' => false,
      'keywordLocation' => '/properties/a/limited',
      'absoluteKeywordLocation' => 'json-schemer://schema#/properties/a/limited',
      'instanceLocation' => '/a',
      'error' => 'value at `/a` is more than 10'
    }
    assert_equal(expected, schemer.validate({ 'a' => 11 }, :output_format => 'detailed'))
    assert_equal([expected], schemer.validate({ 'a' => 11 }, :output_format => 'basic').fetch('errors').to_a)
    assert(schemer.validate({ 'a' => 10 }, :output_format => 'detailed').fetch('valid'))

    error = schemer.validate({ 'a' => 11 }).first
    assert_equal('value at `/a` is more than 10', error.fetch('error'))
    assert_equal('is more than 10', error.fetch('type'))
    assert_equal({ 'keyword' => 'limited', 'result' => 'is more than 10' }, error.fetch('details'))
    assert_equal('/properties/a', error.fetch('schema_pointer'))
    assert_equal('/a', error.fetch('data_pointer'))
  end

  def test_custom_keyword_error_without_message
    schemer = JSONSchemer.schema({ 'even' => true }, :keywords => { 'even' => ->(instance, *) { instance.even? } })
    output = schemer.validate(3, :output_format => 'detailed')
    assert_equal('/even', output.fetch('keywordLocation'))
    assert_equal('value at root does not match schema', output.fetch('error'))
    error = schemer.validate(3).first
    assert_equal('even', error.fetch('type'))
    assert_equal('value at root does not match schema', error.fetch('error'))
  end

  def test_custom_keyword_errors
    schemer = JSONSchemer.schema({ 'two' => true }, :keywords => { 'two' => ->(instance, *) { instance == 2 ? [] : [false, 'is not two', 'is odd'] } })
    keyword_errors = schemer.validate(3, :output_format => 'basic').fetch('errors').select { |error| error.fetch('keywordLocation') == '/two' }
    assert_equal(['value at root does not match schema', 'value at root is not two', 'value at root is odd'], keyword_errors.map { |error| error.fetch('error') })
    assert_equal(['two', 'is not two', 'is odd'], schemer.validate(3).map { |error| error.fetch('type') })
  end

  def test_custom_keyword_x_error_and_i18n
    schema = { '$id' => 'https://example.com/schema', 'properties' => { 'a' => { 'limited' => true } } }
    x_error_schema = { 'properties' => { 'a' => { 'limited' => true, 'x-error' => { 'limited' => '%{keywordLocation}: %{details__result}' } } } }
    assert_equal('/properties/a/limited: is more than 10', JSONSchemer.schema(x_error_schema, :keywords => { 'limited' => LIMITED }).validate({ 'a' => 11 }, :output_format => 'detailed').fetch('error'))

    i18n({ 'https://example.com/schema#/properties/a/limited' => 'too big (%{details__result})' }) do
      assert_equal('too big (is more than 10)', JSONSchemer.schema(schema, :keywords => { 'limited' => LIMITED }).validate({ 'a' => 11 }, :output_format => 'detailed').fetch('error'))
    end
    i18n({ 'limited' => 'limited by keyword name' }) do
      assert_equal('limited by keyword name', JSONSchemer.schema(schema, :keywords => { 'limited' => LIMITED }).validate({ 'a' => 11 }).first.fetch('error'))
    end
  end

  def test_i18n_details_as_hash
    schema = {
      'properties' => {
        'yah' => {
          'type' => 'string'
        }
      },
      'required' => ['yah']
    }

    schemer = JSONSchemer.schema(schema)
    data = {}

    errors = {
      '#/required' => 'missing %{details} %{details__missing_keys}',
    }

    i18n(errors) do
      assert_match(optional_space_regexp('missing {"missing_keys"', '=>', '["yah"]} ["yah"]'), schemer.validate(data, :output_format => 'detailed').fetch('error'))
    end
  end

  def test_i18n_error
    schema = {
      '$id' => 'https://example.com/schema',
      '$schema' => 'https://json-schema.org/draft/2019-09/schema',
      'properties' => {
        'yah' => {
          'type' => 'string'
        }
      }
    }
    schemer = JSONSchemer.schema(schema)
    data = { 'yah' => 1 }

    errors = {
      'https://example.com/schema#' => 'A',
      'https://example.com/schema#/properties/yah/type' => '1',
      'https://example.com/schema' => {
        '#' => 'B',
        '#/properties/yah/type' => '2',
        '^' => 'D',
        'type' => '4',
        '*' => 'E/5'
      },
      '#/properties/yah/type' => '3',
      '#' => 'C',
      'https://json-schema.org/draft/2019-09/schema' => {
        '^' => 'F',
        'type' => '6',
        '*' => 'G/7'
      },
      '^' => 'H',
      'type' => '8 %{keywordValue}',
      '*' => 'I/9: %{instance} %{instanceLocation} %{formattedInstanceLocation} %{keywordLocation} %{absoluteKeywordLocation} %{details}',

      'https://example.com/differentschema#/properties/yah/type' => '?',
      'https://example.com/differentschema' => {
        '#/properties/yah/type' => '?',
        'type' => '?',
        '*' => '?'
      },
      '?' => '?'
    }

    i18n(errors) do
      assert_equal('A', schemer.validate(data, :output_format => 'basic').fetch('error'))
      assert_equal('1', schemer.validate(data).first.fetch('error'))
    end

    errors.delete('https://example.com/schema#')
    assert_equal('B', i18n(errors) { schemer.validate(data, :output_format => 'basic').fetch('error') })

    errors.delete('https://example.com/schema#/properties/yah/type')
    assert_equal('2', i18n(errors) { schemer.validate(data).first.fetch('error') })

    errors.fetch('https://example.com/schema').delete('#')
    assert_equal('C', i18n(errors) { schemer.validate(data, :output_format => 'basic').fetch('error') })

    errors.fetch('https://example.com/schema').delete('#/properties/yah/type')
    assert_equal('3', i18n(errors) { schemer.validate(data).first.fetch('error') })

    errors.delete('#')
    assert_equal('D', i18n(errors) { schemer.validate(data, :output_format => 'basic').fetch('error') })

    errors.delete('#/properties/yah/type')
    assert_equal('4', i18n(errors) { schemer.validate(data).first.fetch('error') })

    errors.fetch('https://example.com/schema').delete('^')
    assert_equal('E/5', i18n(errors) { schemer.validate(data, :output_format => 'basic').fetch('error') })

    errors.fetch('https://example.com/schema').delete('type')
    assert_equal('E/5', i18n(errors) { schemer.validate(data).first.fetch('error') })

    errors.fetch('https://example.com/schema').delete('*')
    i18n(errors) do
      assert_equal('F', schemer.validate(data, :output_format => 'basic').fetch('error'))
      assert_equal('6', schemer.validate(data).first.fetch('error'))
    end

    errors.fetch('https://json-schema.org/draft/2019-09/schema').delete('^')
    assert_equal('G/7', i18n(errors) { schemer.validate(data, :output_format => 'basic').fetch('error') })

    errors.fetch('https://json-schema.org/draft/2019-09/schema').delete('type')
    assert_equal('G/7', i18n(errors) { schemer.validate(data).first.fetch('error') })

    errors.fetch('https://json-schema.org/draft/2019-09/schema').delete('*')
    i18n(errors) do
      assert_equal('H', schemer.validate(data, :output_format => 'basic').fetch('error'))
      assert_equal('8 string', schemer.validate(data).first.fetch('error'))
    end

    errors.delete('^')
    assert_match(optional_space_regexp('I/9: {"yah"', '=>', '1}  root  https://example.com/schema# '), i18n(errors) { schemer.validate(data, :output_format => 'basic').fetch('error') })

    errors.delete('type')
    assert_equal('I/9: 1 /yah `/yah` /properties/yah/type https://example.com/schema#/properties/yah/type ', i18n(errors) { schemer.validate(data).first.fetch('error') })

    i18n(errors) do
      assert_equal(true, schemer.validate(data).first.fetch('i18n'))
      refute(schemer.validate(data).first.key?('x-error'))
      assert_equal(true, schemer.validate(data, :output_format => 'basic').fetch('i18n'))
      refute(schemer.validate(data, :output_format => 'basic').key?('x-error'))
    end

    errors.delete('*')
    i18n(errors) do
      assert_equal('value at root does not match schema', schemer.validate(data, :output_format => 'basic').fetch('error'))
      assert_equal('value at `/yah` is not a string', schemer.validate(data).first.fetch('error'))

      refute(schemer.validate(data).first.key?('i18n'))
      refute(schemer.validate(data).first.key?('x-error'))
      refute(schemer.validate(data, :output_format => 'basic').key?('i18n'))
      refute(schemer.validate(data, :output_format => 'basic').key?('x-error'))
    end
  end

private

  def optional_space_regexp(*parts)
    /\A#{parts.map { |part| Regexp.escape(part) }.join('\s?')}\z/
  end

  def i18n(errors)
    require 'yaml'
    require 'i18n'
    # require 'i18n/debug'

    JSONSchemer.remove_class_variable(:@@i18n) if JSONSchemer.class_variable_defined?(:@@i18n)
    # @on_lookup ||= I18n::Debug.on_lookup
    # I18n::Debug.on_lookup(&@on_lookup)

    Tempfile.create(['translations', '.yml']) do |file|
      file.write(YAML.dump({ 'en' => { 'json_schemer' => { 'errors' => errors } } }))
      file.flush

      I18n.load_path += [file.path]

      yield
    ensure
      I18n.load_path -= [file.path]
    end
  ensure
    JSONSchemer.remove_class_variable(:@@i18n)
    # I18n::Debug.on_lookup {}
  end
end
