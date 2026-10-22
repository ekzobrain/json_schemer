require 'test_helper'

class DeepValidationTest < Minitest::Test
  def resolver(documents, calls = nil)
    proc do |uri|
      calls << uri.to_s if calls
      documents[uri.to_s]
    end
  end

  def deep(schema, documents, base_uri: 'file:///root.json', **options)
    JSONSchemer.validate_schema(schema, :deep => true, :base_uri => URI(base_uri), :ref_resolver => resolver(documents), **options)
  end

  def error_locations(output)
    output.map { |error| error.fetch('data_uri') }.uniq
  end

  def test_valid_documents
    calls = []
    documents = {
      'file:///node.json' => { 'type' => 'object', 'properties' => { 'branches' => { 'type' => 'array', 'items' => { '$ref' => 'branch.json' } } } },
      'file:///branch.json' => { 'type' => 'object', 'properties' => { 'node' => { '$ref' => 'node.json' }, 'leaf' => { '$ref' => 'defs.json#/$defs/leaf' } } },
      'file:///defs.json' => { '$defs' => { 'leaf' => { '$anchor' => 'leaf', 'type' => 'string' } } }
    }
    schema = { 'properties' => { 'tree' => { '$ref' => 'node.json' }, 'leaf' => { '$ref' => 'defs.json#leaf' } } }
    options = { :deep => true, :base_uri => URI('file:///root.json'), :ref_resolver => resolver(documents, calls) }

    assert_equal([], JSONSchemer.validate_schema(schema, **options).to_a)
    assert_equal({ 'valid' => true, 'errors' => [] }, JSONSchemer.validate_schema(schema, :output_format => 'basic', **options))
    assert(JSONSchemer.valid_schema?(schema, **options))
    # documents are retrieved once per validation, cycles end
    assert_equal(['file:///node.json', 'file:///branch.json', 'file:///defs.json'], calls.uniq)
    assert_equal(calls.uniq, calls.first(3))
    assert_equal(9, calls.size)
  end

  def test_invalid_referenced_document
    documents = {
      'file:///error.json' => { 'type' => 'object', 'properties' => { 'code' => { 'type' => 'intger' } } }
    }
    schema = { 'properties' => { 'error' => { '$ref' => 'error.json' } } }

    refute(JSONSchemer.valid_schema?(schema, :base_uri => URI('file:///root.json'), :ref_resolver => resolver(documents)) == false)
    refute(JSONSchemer.valid_schema?(schema, :deep => true, :base_uri => URI('file:///root.json'), :ref_resolver => resolver(documents)))

    output = deep(schema, documents)
    assert_equal(['file:///error.json#/properties/code/type'], error_locations(output))
    assert_equal(['/properties/code/type'], output.map { |error| error.fetch('data_pointer') }.uniq)

    basic = deep(schema, documents, :output_format => 'basic')
    refute(basic.fetch('valid'))
    assert_equal(['file:///error.json#/properties/code/type'], basic.fetch('errors').map { |error| error.fetch('absoluteInstanceLocation') }.uniq)
    assert_equal({ 'valid' => false }, deep(schema, documents, :output_format => 'flag'))
  end

  def test_unresolvable_references
    documents = {
      'file:///defs.json' => { '$defs' => { 'a' => { 'type' => 'string' } } },
      'file:///invalid.json' => { '$defs' => { 'a' => { 'type' => 'intger' } } }
    }
    schema = {
      'properties' => {
        'missing_document' => { '$ref' => 'missing.json' },
        'missing_pointer' => { '$ref' => 'defs.json#/$defs/b' },
        'missing_anchor' => { '$ref' => 'defs.json#b' },
        'missing_local_pointer' => { '$ref' => '#/$defs/b' },
        'missing_pointer_in_invalid_document' => { '$ref' => 'invalid.json#/$defs/b' },
        'valid' => { '$ref' => 'defs.json#/$defs/a' }
      }
    }

    output = deep(schema, documents)
    ref_errors = output.select { |error| error.fetch('type') == 'ref' }
    assert_equal(
      [
        ['file:///root.json#/properties/missing_document/$ref', { 'value' => 'missing.json', 'uri' => 'file:///missing.json' }],
        ['file:///root.json#/properties/missing_pointer/$ref', { 'value' => 'defs.json#/$defs/b', 'uri' => 'file:///defs.json#/$defs/b' }],
        ['file:///root.json#/properties/missing_anchor/$ref', { 'value' => 'defs.json#b', 'uri' => 'file:///defs.json#b' }],
        ['file:///root.json#/properties/missing_local_pointer/$ref', { 'value' => '#/$defs/b', 'uri' => 'file:///root.json#/$defs/b' }],
        ['file:///root.json#/properties/missing_pointer_in_invalid_document/$ref', { 'value' => 'invalid.json#/$defs/b', 'uri' => 'file:///invalid.json#/$defs/b' }]
      ],
      ref_errors.map { |error| [error.fetch('data_uri'), error.fetch('ref')] }
    )
    assert_equal(
      [
        "value at `/properties/missing_document/$ref` references `missing.json`, which can't be retrieved: not found",
        "value at `/properties/missing_pointer/$ref` references `defs.json#/$defs/b`, but pointer `/$defs/b` doesn't exist in `file:///defs.json`",
        "value at `/properties/missing_anchor/$ref` references `defs.json#b`, which doesn't exist in `file:///defs.json`",
        "value at `/properties/missing_local_pointer/$ref` references `#/$defs/b`, but pointer `/$defs/b` doesn't exist in `file:///root.json`",
        "value at `/properties/missing_pointer_in_invalid_document/$ref` references `invalid.json#/$defs/b`, but pointer `/$defs/b` doesn't exist in `file:///invalid.json`"
      ],
      ref_errors.map { |error| error.fetch('error') }
    )
    assert_equal(['file:///invalid.json#/$defs/a/type'], error_locations(output - ref_errors))

    basic = deep(schema, documents, :output_format => 'basic').fetch('errors').select { |error| error.key?('ref') }
    assert_equal(ref_errors.map { |error| error.fetch('error') }, basic.map { |error| error.fetch('error') })
    assert_equal(ref_errors.map { |error| error.fetch('data_pointer') }, basic.map { |error| error.fetch('instanceLocation') })
  end

  def test_pointers_into_invalid_document
    documents = { 'file:///invalid.json' => { 'type' => 'intger', 'allOf' => [true], '$defs' => { 'a' => { 'type' => 'string' } } } }
    schema = {
      'allOf' => [
        { '$ref' => 'invalid.json#/$defs/a' },
        { '$ref' => 'invalid.json#/allOf/0' },
        { '$ref' => 'invalid.json#/allOf/1' },
        { '$ref' => 'invalid.json#/allOf/x' },
        { '$ref' => 'invalid.json#/type/x' }
      ]
    }
    output = deep(schema, documents).select { |error| error.fetch('type') == 'ref' }
    assert_equal(['/allOf/2/$ref', '/allOf/3/$ref', '/allOf/4/$ref'], output.map { |error| error.fetch('data_pointer') })
  end

  def test_referenced_document_compile_error
    documents = { 'file:///a.json' => { '$vocabulary' => { 'https://example.com/unknown' => true } } }
    output = deep({ '$ref' => 'a.json' }, documents)
    assert_equal(["value at `/$ref` references `a.json`, which can't be resolved: https://example.com/unknown"], output.map { |error| error.fetch('error') })
  end

  def test_flag_output_with_reference_errors
    assert_equal({ 'valid' => false }, deep({ '$ref' => 'missing.json' }, {}, :output_format => 'flag'))
    refute(JSONSchemer.valid_schema?({ '$ref' => 'missing.json' }, :deep => true))
    assert(JSONSchemer.valid_schema?({ '$ref' => '#/$defs/a', '$defs' => { 'a' => true } }, :deep => true))
  end

  def test_resolver_errors
    failing_resolver = proc do |uri|
      raise IOError, "can't read #{uri.path}" if uri.path == '/broken.json'
      raise JSONSchemer::UnknownRef, uri.to_s
    end
    schema = { 'properties' => { 'a' => { '$ref' => 'broken.json' }, 'b' => { '$ref' => 'unknown.json' } } }
    output = JSONSchemer.validate_schema(schema, :deep => true, :base_uri => URI('file:///root.json'), :ref_resolver => failing_resolver)
    assert_equal(
      [
        "value at `/properties/a/$ref` references `broken.json`, which can't be retrieved: can't read /broken.json",
        "value at `/properties/b/$ref` references `unknown.json`, which can't be retrieved: file:///unknown.json"
      ],
      output.map { |error| error.fetch('error') }
    )
    # the default resolver doesn't retrieve anything
    output = JSONSchemer.validate_schema(schema, :deep => true)
    assert_equal(['json-schemer://schema#/properties/a/$ref', 'json-schemer://schema#/properties/b/$ref'], error_locations(output))
  end

  def test_document_meta_schemas
    documents = {
      # its own `$schema`: draft 7 `exclusiveMaximum` is a number
      'file:///draft7.json' => { '$schema' => 'http://json-schema.org/draft-07/schema#', 'maximum' => 1, 'exclusiveMaximum' => true },
      # draft 4 boolean `exclusiveMaximum`, valid with the referring schema's draft 4 meta schema
      'file:///inherited.json' => { 'maximum' => 1, 'exclusiveMaximum' => true }
    }
    schema = {
      '$schema' => 'http://json-schema.org/draft-04/schema#',
      'properties' => { 'a' => { '$ref' => 'draft7.json' }, 'b' => { '$ref' => 'inherited.json' } }
    }
    assert_equal(['file:///draft7.json#/exclusiveMaximum'], error_locations(deep(schema, documents)))
    refute_empty(deep(schema.merge('$schema' => 'https://json-schema.org/draft/2020-12/schema'), documents).select { |error| error.fetch('data_uri') == 'file:///inherited.json#/exclusiveMaximum' })
  end

  def test_dynamic_ref_and_embedded_resources
    documents = {
      'file:///tree.json' => {
        '$dynamicAnchor' => 'node',
        'type' => 'object',
        'properties' => { 'children' => { 'type' => 'array', 'items' => { '$dynamicRef' => '#node' } } },
        '$defs' => { 'leaf' => { '$id' => 'leaf.json', 'type' => 'string', 'minLength' => -1 } }
      }
    }
    output = deep({ '$ref' => 'tree.json' }, documents)
    assert_equal(['file:///tree.json#/$defs/leaf/minLength'], error_locations(output))

    documents['file:///tree.json']['$defs']['leaf']['minLength'] = 1
    assert_equal([], deep({ '$ref' => 'tree.json', 'properties' => { 'leaf' => { '$ref' => 'tree.json#/$defs/leaf' } } }, documents))

    # an identifier declared in another document isn't known to the referring one (as when validating instances)
    output = deep({ '$ref' => 'tree.json', 'properties' => { 'leaf' => { '$ref' => 'leaf.json' } } }, documents)
    assert_equal(['file:///root.json#/properties/leaf/$ref'], error_locations(output))
  end

  def test_draft7_ref_with_siblings
    documents = { 'file:///a.json' => { 'type' => 'string' } }
    schema = { '$schema' => 'http://json-schema.org/draft-07/schema#', 'definitions' => { 'a' => { '$ref' => 'a.json', 'type' => 'intger' } } }
    # siblings of `$ref` are ignored in draft 7, but still validated against the meta schema
    assert_equal(['file:///root.json#/definitions/a/type'], error_locations(deep(schema, documents)))
  end

  def test_invalid_root
    documents = { 'file:///a.json' => { 'type' => 'intger' } }
    schema = { 'type' => 'objct', 'properties' => { 'a' => { '$ref' => 'a.json' } } }
    # an invalid root isn't compiled, so its references aren't followed
    assert_equal(['file:///root.json#/type'], error_locations(deep(schema, documents)))
  end

  def test_root_compile_error
    output = deep({ '$vocabulary' => { 'https://example.com/unknown' => true } }, {})
    assert_equal(['file:///root.json#'], error_locations(output))
    assert_equal(['compile'], output.map { |error| error.fetch('type') })
    assert_equal("value at root schema can't be compiled: https://example.com/unknown", output.first.fetch('error'))
  end

  def test_unknown_meta_schema
    output = deep({ '$schema' => 'https://example.com/unknown' }, {})
    assert_equal(['schema'], output.map { |error| error.fetch('type') })
    assert_equal(['file:///root.json#'], error_locations(output))

    output = deep({ '$ref' => 'a.json' }, { 'file:///a.json' => { '$schema' => 'https://example.com/unknown' } })
    assert_equal(['file:///a.json#'], error_locations(output))
    assert_match(/\Avalue at root has an unknown meta schema: /, output.first.fetch('error'))
  end

  def test_invalid_reference
    # rejected by the meta schema (`uri-reference` format)
    assert_equal(['file:///root.json#/$ref'], error_locations(deep({ '$ref' => 'http://[bad' }, {})))
    # draft 4 meta schema doesn't describe `$ref`
    output = deep({ '$schema' => 'http://json-schema.org/draft-04/schema#', 'properties' => { 'a' => { '$ref' => 'http://[bad' } } }, {})
    assert_equal(['file:///root.json#/properties/a/$ref'], error_locations(output))
    assert_match(/\Avalue at `\/properties\/a\/\$ref` has an invalid reference `http:\/\/\[bad`: /, output.first.fetch('error'))
  end

  def test_max_documents
    documents = {
      'file:///a.json' => { '$ref' => 'b.json' },
      'file:///b.json' => { '$ref' => 'c.json' },
      'file:///c.json' => true
    }
    assert_equal([], deep({ '$ref' => 'a.json' }, documents, :max_documents => 3))
    output = deep({ '$ref' => 'a.json' }, documents, :max_documents => 2)
    assert_equal(['file:///b.json#/$ref'], error_locations(output))
    assert_equal("value at `/$ref` references `c.json`, which can't be retrieved: more than 2 documents referenced", output.first.fetch('error'))
  end

  def test_schema_validate_schema
    documents = { 'file:///a.json' => { 'type' => 'intger' } }
    schemer = JSONSchemer.schema({ '$ref' => 'a.json' }, :base_uri => URI('file:///root.json'), :ref_resolver => resolver(documents))
    assert(schemer.valid_schema?)
    assert_equal([], schemer.validate_schema.to_a)
    refute(schemer.valid_schema?(:deep => true))
    assert_equal(['file:///a.json#/type'], error_locations(schemer.validate_schema(:deep => true)))
    assert_equal(['file:///a.json#/type'], schemer.validate_schema(:deep => true, :output_format => 'basic').fetch('errors').map { |error| error.fetch('absoluteInstanceLocation') }.uniq)
    # the schema itself isn't changed (its references aren't resolved)
    assert_raises(JSONSchemer::UnknownRef) { JSONSchemer.schema({ '$ref' => 'a.json' }).valid?(1) }
  end

  def test_files
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'root.json'), JSON.generate({ 'properties' => { 'a' => { '$ref' => 'a.json' }, 'b' => { '$ref' => 'b.json' } } }))
      File.write(File.join(dir, 'a.json'), JSON.generate({ 'type' => 'intger' }))
      output = JSONSchemer.validate_schema(Pathname.new(File.join(dir, 'root.json')), :deep => true)
      a_uri = URI.join('file:', File.join(File.realpath(dir), 'a.json')).to_s
      assert_equal(["#{a_uri}#/type", "#{File.dirname(a_uri)}/root.json#/properties/b/$ref"], error_locations(output))
    end
  end

  def test_root_identified_by_id
    output = JSONSchemer.validate_schema({ '$id' => 'http://example.com/schema', '$ref' => 'missing' }, :deep => true)
    assert_equal(['http://example.com/schema#/$ref'], error_locations(output))
    output = JSONSchemer.validate_schema({ '$id' => 'schemas/root', '$ref' => 'missing' }, :deep => true, :base_uri => URI('http://example.com/'))
    assert_equal(['http://example.com/schemas/root#/$ref'], error_locations(output))
    output = JSONSchemer.validate_schema({ '$id' => 'http://[bad', 'type' => 'intger' }, :deep => true)
    assert_equal(['json-schemer://schema#/$id', 'json-schemer://schema#/type'], error_locations(output))
  end

  def test_unsupported_output_format
    assert_raises(JSONSchemer::UnknownOutputFormat) { JSONSchemer.validate_schema({}, :deep => true, :output_format => 'detailed') }
  end
end
