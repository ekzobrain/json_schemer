# JSONSchemer

JSON Schema validator. Supports drafts 4, 6, 7, 2019-09, 2020-12, OpenAPI 3.0, and OpenAPI 3.1.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'json_schemer'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install json_schemer

## Usage

```ruby
require 'json_schemer'

schema = {
  'type' => 'object',
  'properties' => {
    'abc' => {
      'type' => 'integer',
      'minimum' => 11
    }
  }
}
schemer = JSONSchemer.schema(schema)

# true/false validation

schemer.valid?({ 'abc' => 11 })
# => true

schemer.valid?({ 'abc' => 10 })
# => false

# error validation (`validate` returns an enumerator)

schemer.validate({ 'abc' => 10 }).to_a
# => [{"data"=>10,
#      "data_pointer"=>"/abc",
#      "schema"=>{"type"=>"integer", "minimum"=>11},
#      "schema_pointer"=>"/properties/abc",
#      "root_schema"=>{"type"=>"object", "properties"=>{"abc"=>{"type"=>"integer", "minimum"=>11}}},
#      "type"=>"minimum",
#      "error"=>"number at `/abc` is less than: 11"}]

# default property values

data = {}
JSONSchemer.schema(
  {
    'properties' => {
      'foo' => {
        'default' => 'bar'
      }
    }
  },
  insert_property_defaults: true
).valid?(data)
data
# => {"foo"=>"bar"}

# schema files

require 'pathname'

schema = Pathname.new('/path/to/schema.json')
schemer = JSONSchemer.schema(schema)

# schema json string

schema = '{ "type": "integer" }'
schemer = JSONSchemer.schema(schema)

# schema validation

JSONSchemer.valid_schema?({ '$id' => 'valid' })
# => true

JSONSchemer.validate_schema({ '$id' => '#invalid' }).to_a
# => [{"data"=>"#invalid",
#      "data_pointer"=>"/$id",
#      "schema"=>{"$ref"=>"#/$defs/uriReferenceString", "$comment"=>"Non-empty fragments not allowed.", "pattern"=>"^[^#]*#?$"},
#      "schema_pointer"=>"/properties/$id",
#      "root_schema"=>{...meta schema},
#      "type"=>"pattern",
#      "error"=>"string at `/$id` does not match pattern: ^[^#]*#?$"}]

# subschemas

schema = {
  'type' => 'integer',
  '$defs' => {
    'foo' => {
      'type' => 'string'
    }
  }
}
schemer = JSONSchemer.schema(schema)

schemer.ref('#/$defs/foo').validate(1).to_a
# => [{"data"=>1,
#      "data_pointer"=>"",
#      "schema"=>{"type"=>"string"},
#      "schema_pointer"=>"/$defs/foo",
#      "root_schema"=>{"type"=>"integer", "$defs"=>{"foo"=>{"type"=>"string"}}},
#      "type"=>"string",
#      "error"=>"value at root is not a string"}]

# schema bundling (https://json-schema.org/draft/2020-12/json-schema-core.html#section-9.3)

schema = {
  '$id' => 'http://example.com/schema',
  'allOf' => [
    { '$ref' => 'schema/one' },
    { '$ref' => 'schema/two' }
  ]
}
refs = {
  URI('http://example.com/schema/one') => {
    'type' => 'integer'
  },
  URI('http://example.com/schema/two') => {
    'minimum' => 11
  }
}
schemer = JSONSchemer.schema(schema, :ref_resolver => refs.to_proc)

schemer.bundle
# => {"$id"=>"http://example.com/schema",
#     "allOf"=>[{"$ref"=>"schema/one"}, {"$ref"=>"schema/two"}],
#     "$schema"=>"https://json-schema.org/draft/2020-12/schema",
#     "$defs"=>
#      {"http://example.com/schema/one"=>{"type"=>"integer", "$id"=>"http://example.com/schema/one", "$schema"=>"https://json-schema.org/draft/2020-12/schema"},
#       "http://example.com/schema/two"=>{"minimum"=>11, "$id"=>"http://example.com/schema/two", "$schema"=>"https://json-schema.org/draft/2020-12/schema"}}}
```

## Options

```ruby
JSONSchemer.schema(
  schema,

  # meta schema to use for vocabularies (keyword behavior) and schema validation
  # String/JSONSchemer::Schema
  # 'https://json-schema.org/draft/2020-12/schema': JSONSchemer.draft202012
  # 'https://json-schema.org/draft/2019-09/schema': JSONSchemer.draft201909
  # 'http://json-schema.org/draft-07/schema#': JSONSchemer.draft7
  # 'http://json-schema.org/draft-06/schema#': JSONSchemer.draft6
  # 'http://json-schema.org/draft-04/schema#': JSONSchemer.draft4
  # 'http://json-schema.org/schema#': JSONSchemer.draft4
  # 'https://spec.openapis.org/oas/3.1/dialect/base': JSONSchemer.openapi31
  # 'json-schemer://openapi30/schema': JSONSchemer.openapi30
  # default: JSONSchemer.draft202012
  meta_schema: 'https://json-schema.org/draft/2020-12/schema',

  # validate `format` (https://json-schema.org/draft/2020-12/json-schema-validation.html#section-7)
  # true/false
  # default: true
  format: true,

  # custom formats
  formats: {
    'int32' => proc do |instance, _format|
      instance.is_a?(Integer) && instance.bit_length <= 32
    end,
    # disable specific format
    'email' => false
  },

  # custom content encodings
  # only `base64` is available by default
  content_encodings: {
    # return [success, annotation] tuple
    'urlsafe_base64' => proc do |instance|
      [true, Base64.urlsafe_decode64(instance)]
    rescue
      [false, nil]
    end
  },

  # custom content media types
  # only `application/json` is available by default
  content_media_types: {
    # return [success, annotation] tuple
    'text/csv' => proc do |instance|
      [true, CSV.parse(instance)]
    rescue
      [false, nil]
    end
  },

  # insert default property values after validation (and validate again)
  # see "Default Values" below for a single pass alternative
  # string keys by default (use `:symbol` to insert symbol keys)
  # true/false/:symbol
  # default: false
  insert_property_defaults: true,

  # hooks to inspect and modify data during validation (see "Hooks" below)
  # Proc/[Proc]
  # default: []
  before_object_validation: [JSONSchemer::Schema::INSERT_PROPERTY_DEFAULT],
  before_property_validation: proc do |data, property, property_schema, _parent|
    data[property] ||= 42
  end,
  before_value_validation: proc do |data, key, schema, _parent_schema, _location|
    data[key] = data.fetch('items').sum { |item| item.fetch('subtotal') } if schema.value.is_a?(Hash) && schema.value['x-computed'] == 'total'
  end,
  after_value_validation: proc do |data, key, _schema, _parent_schema, _location|
    data[key] = data[key].strip if data[key].is_a?(String)
  end,
  after_property_validation: proc do |data, property, property_schema, _parent|
    data[property] = data[property].downcase if data[property].is_a?(String) && property_schema.is_a?(Hash) && property_schema['format'] == 'email'
  end,
  deferred_value_validation: proc do |data, key, schema, _parent_schema, _location|
    data[key] = Date.iso8601(data[key]) if data[key].is_a?(String) && schema.value.is_a?(Hash) && schema.value['format'] == 'date'
  end,

  # resolve external references
  # 'net/http'/proc/lambda/respond_to?(:call)
  # 'net/http': proc { |uri| JSON.parse(Net::HTTP.get(uri)) }
  # default: proc { |uri| raise UnknownRef, uri.to_s }
  ref_resolver: 'net/http',

  # skip converting schema and instance keys to strings (keys must already be strings)
  # avoids copying data and lets property hooks modify the instance directly
  # can be overridden per call: `schemer.valid?(data, stringified_keys: true)`
  # true/false
  # default: false
  stringified_keys: true,

  # use different method to match regexes
  # 'ruby'/'ecma'/proc/lambda/respond_to?(:call)
  # 'ruby': proc { |pattern| Regexp.new(pattern) }
  # default: 'ruby'
  regexp_resolver: proc do |pattern|
    RE2::Regexp.new(pattern)
  end,

  # output formatting (https://json-schema.org/draft/2020-12/json-schema-core.html#section-12)
  # 'classic'/'flag'/'basic'/'detailed'/'verbose'
  # default: 'classic'
  output_format: 'basic',

  # validate `readOnly`/`writeOnly` keywords (https://spec.openapis.org/oas/v3.0.3#fixed-fields-19)
  # 'read'/'write'/nil
  # default: nil
  access_mode: 'read'
)
```

## Hooks

Hooks are procs (or anything responding to `call`) that are called while data is validated, to inspect or modify it: insert default values, compute values, convert types, collect locations of values, etc. Each option takes one hook or a list of hooks, which are called in the order given.

There are six hooks, called at different times while an object or array is validated:

| Hook | Called | Changes are seen by |
| --- | --- | --- |
| `before_object_validation` | before any keyword of a schema with `properties` validates an object | all keywords of the schema |
| `before_property_validation` | in `properties`, before property values are validated | `properties` and keywords evaluated after it |
| `before_value_validation` | before each value in an object or array is validated, once previous values (and everything nested in them) are | the value's validation, later values and keywords evaluated after the current one |
| `after_value_validation` | after each value in an object or array is validated | later values and keywords evaluated after the current one |
| `after_property_validation` | in `properties`, after property values are validated | keywords evaluated after `properties`, other subschemas and parent schemas |
| `deferred_value_validation` | after the whole instance is validated, for each value in an object or array that was validated | nothing (validation is done) |

For example, with:

```ruby
schema = {
  'properties' => {
    'items' => { 'items' => { 'properties' => { 'price' => {}, 'quantity' => {}, 'subtotal' => {} } } },
    'total' => {}
  }
}
data = { 'items' => [{ 'price' => 10, 'quantity' => 2 }] }
```

hooks are called in this order (`data`: key):

1. `before_object_validation`, `before_property_validation`: root `items`, `total`
2. `before_value_validation`: root `items`
    1. `before_value_validation`: `items` index `0`
        1. `before_object_validation`, `before_property_validation`: item `price`, `quantity`, `subtotal`
        2. `before_value_validation`, `after_value_validation`: item `price`, then `quantity`, then `subtotal`
        3. `after_property_validation`: item `price`, `quantity`, `subtotal`
    2. `after_value_validation`: `items` index `0`
3. `after_value_validation`: root `items`
4. `before_value_validation`, `after_value_validation`: root `total`
5. `after_property_validation`: root `items`, `total`
6. `deferred_value_validation`: item `price`, `quantity`, `subtotal`, `items` index `0`, root `items`, `total`

### Arguments

Hooks are called with:

1. `data`: the object or array being validated
2. `key`: the property name or the array index (`Integer`)
3. `schema`: the `JSONSchemer::Schema` the value is validated with. `schema.value` is the schema as given; the object also resolves references (`schema.parsed['$ref'].ref_schema`), finds defaults behind them (`schema.default_keyword_instance`) and knows its location (`schema.schema_pointer`)
4. `parent_schema`: the `JSONSchemer::Schema` containing the keyword (eg `properties` or `items`)
5. `location`: JSON pointer of `data` in the instance (eg `/items/3`); the value is at `"#{location}/#{key}"`

`before_property_validation` and `after_property_validation` hooks declaring fewer than five parameters (like the ones written for earlier versions) get the original arguments instead: `data`, `property`, `property_schema` and `parent_schema`, with schemas as given (`Hash`/`true`/`false`, references not resolved). Hooks that take any number of arguments (`*args`) get the original arguments too.

Lambdas and methods only get as many arguments as they declare.

### `before_object_validation`

Called when a schema with `properties` starts validating an object, before any of its keywords (including `$ref`, `allOf`, `oneOf`, `if`, `dependentSchemas` and `required`), for every property listed in `properties`, whether or not it is present. Use it to insert default values (see "Default Values" below) and values that only depend on the object itself, so that all keywords see them:

```ruby
kind_default = proc do |data, key, schema|
  data[key] = 'person' if key == 'kind' && !data.key?(key)
end

schemer = JSONSchemer.schema(
  {
    'properties' => { 'kind' => { 'enum' => ['person', 'company'] }, 'name' => {}, 'inn' => {} },
    'if' => { 'properties' => { 'kind' => { 'const' => 'company' } } },
    'then' => { 'required' => ['inn'] },
    'else' => { 'required' => ['name'] }
  },
  before_object_validation: [kind_default]
)

schemer.valid?({ 'inn' => '1' })
# => false (`kind` is "person", so `name` is required)
```

### `before_property_validation`

Called in `properties` before property values are validated, for every property listed in it, whether or not it is present. Keywords evaluated before `properties` (`$ref`, `allOf`, `anyOf`, `oneOf`, `not`, `if`/`then`/`else`, `dependentSchemas`, array keywords) don't see the changes; `properties` and the keywords after it (`patternProperties`, `additionalProperties`, `required`, `dependentRequired`, `enum`, ...) do:

```ruby
parse_list = proc do |data, property, property_schema, _parent|
  data[property] = data[property].split(',') if data[property].is_a?(String) && property_schema.is_a?(Hash) && property_schema['type'] == 'array'
end

data = { 'tags' => 'a,b' }
JSONSchemer.schema({ 'properties' => { 'tags' => { 'type' => 'array' } } }, before_property_validation: [parse_list]).valid?(data)
# => true
data
# => {"tags"=>["a", "b"]}
```

### `before_value_validation`

Called right before each value in an object or array is validated. By then, previous values (and everything nested in them) are validated and processed by hooks, so a value can be computed from them. It's called for values of:

- `properties`: every property listed, whether or not it is present (so values can be inserted)
- `patternProperties`, `additionalProperties`, `unevaluatedProperties`: present properties
- `prefixItems`, `items`, `additionalItems`, `unevaluatedItems`, `contains`: present items

For example, an order total computed from its items' subtotals, which are computed from their price and quantity:

```ruby
compute = proc do |data, key, schema|
  case schema.value.is_a?(Hash) && schema.value['x-computed']
  when 'subtotal'
    data[key] = data.fetch('price') * data.fetch('quantity')
  when 'total'
    data[key] = data.fetch('items').sum { |item| item.fetch('subtotal') }
  end
end

schemer = JSONSchemer.schema(
  {
    'properties' => {
      'items' => {
        'items' => {
          'properties' => {
            'price' => { 'type' => 'integer' },
            'quantity' => { 'type' => 'integer', 'default' => 1 },
            'subtotal' => { 'x-computed' => 'subtotal' }
          }
        }
      },
      'total' => { 'type' => 'integer', 'maximum' => 100, 'x-computed' => 'total' }
    },
    'required' => ['total']
  },
  before_object_validation: [JSONSchemer::Schema::INSERT_PROPERTY_DEFAULT],
  before_value_validation: [compute]
)

data = { 'items' => [{ 'price' => 10 }, { 'price' => 20, 'quantity' => 2 }] }
schemer.valid?(data)
# => true
data
# => {"items"=>[{"price"=>10, "quantity"=>1, "subtotal"=>10}, {"price"=>20, "quantity"=>2, "subtotal"=>40}], "total"=>50}
```

Keywords evaluated before the one validating the value (eg `if` and `oneOf` before `properties`) don't see the changes; see "Keyword Order" below to change that.

### `after_value_validation`

Called right after each value in an object or array is validated, for the same values as `before_value_validation`. Later values and keywords evaluated after the current one see the changes:

```ruby
strip = proc do |data, key|
  data[key] = data[key].strip if data[key].is_a?(String)
end

data = { 'name' => ' Bob ' }
JSONSchemer.schema({ 'properties' => { 'name' => {} }, 'enum' => [{ 'name' => 'Bob' }] }, after_value_validation: [strip]).valid?(data)
# => true
data
# => {"name"=>"Bob"}
```

### `after_property_validation`

Called in `properties` after property values are validated, for every property listed in it, whether or not it is present. Keywords evaluated after `properties`, other subschemas validating the same object (eg in `allOf`) and parent schemas see the changes. That makes it unsuitable for type conversions: a value converted to a `Date` fails a `type: string` validated later. Use `deferred_value_validation` for those.

```ruby
normalize_email = proc do |data, property, property_schema, _parent|
  data[property] = data[property].downcase if data[property].is_a?(String) && property_schema.is_a?(Hash) && property_schema['format'] == 'email'
end
```

### `deferred_value_validation`

Called once the whole instance is validated, for each value in an object or array that was validated (the same values as `before_value_validation`), in validation order: nested values before the values containing them. No keyword sees the changes, so values can be converted to other types, and locations of values can be collected:

```ruby
dates = []
convert_dates = proc do |data, key, schema, _parent_schema, location|
  if data[key].is_a?(String) && schema.value.is_a?(Hash) && schema.value['format'] == 'date'
    dates << "#{location}/#{key}"
    data[key] = Date.iso8601(data[key])
  end
end

schemer = JSONSchemer.schema(
  {
    'properties' => {
      'start' => { 'type' => 'string', 'format' => 'date' },
      'holidays' => { 'items' => { 'type' => 'string', 'format' => 'date' } }
    },
    'patternProperties' => { '^start$' => { 'type' => 'string' } }
  },
  deferred_value_validation: [convert_dates]
)

data = { 'start' => '2020-09-03', 'holidays' => ['2020-12-25'] }
schemer.valid?(data)
# => true
data
# => {"start"=>#<Date: 2020-09-03>, "holidays"=>[#<Date: 2020-12-25>]}
dates
# => ["/start", "/holidays/0"]
```

Values validated by several schemas (here `start` by `properties` and `patternProperties`) get a call from each, with that schema, so hooks should handle values they already processed: here the second call for `start` gets a `Date` and skips it.

### Subschemas That Don't Apply

Subschemas of `anyOf`, `oneOf`, `not`, `if` and `contains` are only tried, so hooks called while trying them are applied in a transaction: every subschema sees the same data, and changes and `deferred_value_validation` calls are kept only for the first valid `anyOf` subschema, the valid `oneOf` subschema (if exactly one is valid), a matching `if` and matching `contains` items. To be rolled back correctly, hooks must only assign values of the object or array they're given (`data[key] = value`) rather than modify nested objects in place.

### Repeated Calls

Hooks are called by the keywords validating a value, so a value validated by several schemas (eg in `allOf`, `$ref` next to `properties`, or `properties` and `patternProperties`) gets a call from each, with that schema. Hooks should be idempotent, eg not convert a value that's already converted.

In schemas where `$ref` overrides sibling keywords (draft 7 and earlier), hooks only run for the referenced schema.

### Default Values

There are two ways to insert `default` values of missing properties:

- `insert_property_defaults: true` (or `:symbol` to insert symbol keys): after the instance is validated, defaults are inserted where the subschemas that define them were valid, and the instance is validated again, so validation and hooks run twice. When subschemas define different defaults for the same property, none is inserted.
- `JSONSchemer::Schema::INSERT_PROPERTY_DEFAULT` hook, recommended in `before_object_validation`: defaults are inserted before the object is validated, so every keyword (`$ref`, `oneOf`, `if`, `required`, ...) sees them, in a single validation pass. Defaults from subschemas that don't apply (eg `oneOf` branches) are rolled back. When subschemas define different defaults for the same property, the first one that applies (in keyword evaluation order) is inserted and the others validate it. Defaults are deep copied and found behind `$ref`, `$dynamicRef` and `$recursiveRef` like with `insert_property_defaults`.

```ruby
schemer = JSONSchemer.schema(
  {
    'properties' => { 'kind' => { 'default' => 'a' } },
    'oneOf' => [
      { 'properties' => { 'kind' => { 'const' => 'a' } }, 'required' => ['kind'] },
      { 'properties' => { 'kind' => { 'const' => 'b' } }, 'required' => ['kind'] }
    ]
  },
  before_object_validation: [JSONSchemer::Schema::INSERT_PROPERTY_DEFAULT]
)

data = {}
schemer.valid?(data)
# => true
data
# => {"kind"=>"a"}
```

The hook also works in `before_property_validation` and `before_value_validation`, but keywords evaluated before `properties` (like `oneOf` above) don't see the defaults then.

### Keyword Order

Keywords of a schema are evaluated in a fixed order: `$ref` and other core keywords first, then applicators (`allOf`, `anyOf`, `oneOf`, `not`, `if`/`then`/`else`, `dependentSchemas`, array keywords, `properties`, `patternProperties`, `additionalProperties`, ...), then validation keywords (`type`, `enum`, `required`, ...) and `unevaluatedItems`/`unevaluatedProperties`. The order doesn't change validation results, but it decides which keywords see changes made by `before_property_validation`, `before_value_validation`, `after_value_validation` and `after_property_validation` hooks: by default `allOf`, `anyOf`, `oneOf`, `if` and `dependentSchemas` are evaluated before `properties`, so they don't see values computed there.

The order comes from the meta schema's `keyword_order` (keyword => position) and is applied when schemas are parsed. To evaluate `properties` before other applicators, change it in a meta schema before creating schemas:

```ruby
def properties_first(meta_schema)
  keywords = meta_schema.keyword_order.keys
  keywords.delete('properties')
  keywords.insert(keywords.index('allOf'), 'properties')
  meta_schema.keyword_order = keywords.each_with_index.to_h
end

# for all draft 2020-12 schemas in the process (including ones with `$schema`)
properties_first(JSONSchemer.draft202012)

# or only for schemas using a separate meta schema (passed as `meta_schema:`; schemas with a `$schema` keyword use the global meta schema instead)
meta_schema = JSONSchemer::Schema.new(
  JSONSchemer::Draft202012::SCHEMA,
  base_uri: JSONSchemer::Draft202012::BASE_URI,
  formats: JSONSchemer::Draft202012::FORMATS,
  content_encodings: JSONSchemer::Draft202012::CONTENT_ENCODINGS,
  content_media_types: JSONSchemer::Draft202012::CONTENT_MEDIA_TYPES,
  ref_resolver: JSONSchemer::Draft202012::Meta::SCHEMAS.to_proc,
  regexp_resolver: 'ecma'
)
properties_first(meta_schema)
JSONSchemer.schema(schema, meta_schema: meta_schema)
```

Other drafts have their own meta schemas (`JSONSchemer.draft201909`, `JSONSchemer.draft7`, ...). Core keywords (`$ref`, `$dynamicRef`) are evaluated before applicators and can be moved the same way. `then`/`else` must stay after `if`, `items` after `prefixItems`, `additionalProperties` after `properties`/`patternProperties` and `unevaluatedItems`/`unevaluatedProperties` last, since they use those keywords' results.

## Global Configuration

Configuration options can be set globally by modifying `JSONSchemer.configuration`. Global options are applied to any new schemas at creation time (global configuration changes are not reflected in existing schemas). They can be overridden with the regular keyword arguments described [above](#options).

```ruby
# configuration block
JSONSchemer.configure do |config|
  config.regexp_resolver = 'ecma'
end

# configuration accessors
JSONSchemer.configuration.insert_property_defaults = true
```

## Custom Error Messages

Error messages can be customized using the `x-error` keyword and/or [I18n](https://github.com/ruby-i18n/i18n) translations. `x-error` takes precedence if both are defined.

### `x-error` Keyword

```ruby
# override all errors for a schema
schemer = JSONSchemer.schema({
  'type' => 'string',
  'x-error' => 'custom error for schema and all keywords'
})

schemer.validate(1).first
# => {"data"=>1,
#     "data_pointer"=>"",
#     "schema"=>{"type"=>"string", "x-error"=>"custom error for schema and all keywords"},
#     "schema_pointer"=>"",
#     "root_schema"=>{"type"=>"string", "x-error"=>"custom error for schema and all keywords"},
#     "type"=>"string",
#     "error"=>"custom error for schema and all keywords",
#     "x-error"=>true}

schemer.validate(1, :output_format => 'basic')
# => {"valid"=>false,
#     "keywordLocation"=>"",
#     "absoluteKeywordLocation"=>"json-schemer://schema#",
#     "instanceLocation"=>"",
#     "error"=>"custom error for schema and all keywords",
#     "x-error"=>true,
#     "errors"=>#<Enumerator: ...>}

# keyword-specific errors
schemer = JSONSchemer.schema({
  'type' => 'string',
  'minLength' => 10,
  'x-error' => {
    'type' => 'custom error for `type` keyword',
    # special `^` keyword for schema-level error
    '^' => 'custom error for schema',
    # same behavior as when `x-error` is a string
    '*' => 'fallback error for schema and all keywords'
  }
})

schemer.validate(1).map { _1.fetch('error') }
# => ["custom error for `type` keyword"]

schemer.validate('1').map { _1.fetch('error') }
# => ["custom error for schema and all keywords"]

schemer.validate(1, :output_format => 'basic').fetch('error')
# => "custom error for schema"

# variable interpolation (instance/instanceLocation/formattedInstanceLocation/keywordValue/keywordLocation/absoluteKeywordLocation/details)
schemer = JSONSchemer.schema({
  '$id' => 'https://example.com/schema',
  'properties' => {
    'abc' => {
      'type' => 'object',
      'required' => ['xyz'],
      'x-error' => <<~ERROR
        instance: %{instance}
        instance location: %{instanceLocation}
        formatted instance location: %{formattedInstanceLocation}
        keyword value: %{keywordValue}
        keyword location: %{keywordLocation}
        absolute keyword location: %{absoluteKeywordLocation}
        details: %{details}
        details__missing_keys: %{details__missing_keys}
      ERROR
    }
  }
})

puts schemer.validate({ 'abc' => {} }).first.fetch('error')
# instance: {}
# instance location: /abc
# formatted instance location: `/abc`
# keyword value: ["xyz"]
# keyword location: /properties/abc/required
# absolute keyword location: https://example.com/schema#/properties/abc/required
# details: {"missing_keys" => ["xyz"]}
# details__missing_keys: ["xyz"]
```

### I18n

When the [I18n gem](https://github.com/ruby-i18n/i18n) is loaded, custom error messages are looked up under the `json_schemer` key. It may be necessary to restart your application after adding the root key because the existence check is cached for performance reasons.

Translation keys are looked up in this order:

1. `$LOCALE.json_schemer.errors.$ABSOLUTE_KEYWORD_LOCATION`
2. `$LOCALE.json_schemer.errors.$SCHEMA_ID.$KEYWORD_LOCATION`
3. `$LOCALE.json_schemer.errors.$KEYWORD_LOCATION`
4. `$LOCALE.json_schemer.errors.$SCHEMA_ID.$KEYWORD`
5. `$LOCALE.json_schemer.errors.$SCHEMA_ID.*`
6. `$LOCALE.json_schemer.errors.$META_SCHEMA_ID.$KEYWORD`
7. `$LOCALE.json_schemer.errors.$META_SCHEMA_ID.*`
8. `$LOCALE.json_schemer.errors.$KEYWORD`
9. `$LOCALE.json_schemer.errors.*`

Example translations file:

```yaml
en:
  json_schemer:
    errors:
      # variable interpolation (instance/instanceLocation/formattedInstanceLocation/keywordValue/keywordLocation/absoluteKeywordLocation/details)
      'https://example.com/schema#/properties/abc/required': |
        custom error for absolute keyword location
        instance: %{instance}
        instance location: %{instanceLocation}
        formatted instance location: %{formattedInstanceLocation}
        keyword value: %{keywordValue}
        keyword location: %{keywordLocation}
        absolute keyword location: %{absoluteKeywordLocation}
        details: %{details}
        details__missing_keys: %{details__missing_keys}
      'https://example.com/schema':
        '#/properties/abc/required': custom error for keyword location, nested under schema $id
        'required': custom error for `required` keyword, nested under schema $id
        '^': custom error for schema, nested under schema $id
        '*': fallback error for schema and all keywords, nested under schema $id
      '#/properties/abc/required': custom error for keyword location
      'http://json-schema.org/draft-07/schema#':
        'required': custom error for `required` keyword, nested under meta-schema $id ($schema)
        '^': custom error for schema, nested under meta-schema $id
        '*': fallback error for schema and all keywords, nested under meta-schema $id ($schema)
      'required': custom error for `required` keyword
      '^': custom error for schema
      '*': fallback error for schema and all keywords
```

And output:

```ruby
require 'i18n'
I18n.locale = :en                                         # $LOCALE=en

schemer = JSONSchemer.schema({
  '$id' => 'https://example.com/schema',                  # $SCHEMA_ID=https://example.com/schema
  '$schema' => 'http://json-schema.org/draft-07/schema#', # $META_SCHEMA_ID=http://json-schema.org/draft-07/schema#
  'properties' => {
    'abc' => {
      'required' => ['xyz']                               # $KEYWORD=required
    }                                                     # $KEYWORD_LOCATION=#/properties/abc/required
  }                                                       # $ABSOLUTE_KEYWORD_LOCATION=https://example.com/schema#/properties/abc/required
})

schemer.validate({ 'abc' => {} }).first
# => {"data" => {},
#     "data_pointer" => "/abc",
#     "schema" => {"required" => ["xyz"]},
#     "schema_pointer" => "/properties/abc",
#     "root_schema" => {"$id" => "https://example.com/schema", "$schema" => "http://json-schema.org/draft-07/schema#", "properties" => {"abc" => {"required" => ["xyz"]}}},
#     "type" => "required",
#     "error" =>
#      "custom error for absolute keyword location\ninstance: {}\ninstance location: /abc\nformatted instance location: `/abc`\nkeyword value: [\"xyz\"]\nkeyword location: /properties/abc/required\nabsolute keyword location: https://example.com/schema#/properties/abc/required\ndetails: {\"missing_keys\" => [\"xyz\"]}\ndetails__missing_keys: [\"xyz\"]\n",
#     "i18n" => true,
#     "details" => {"missing_keys" => ["xyz"]}}

puts schemer.validate({ 'abc' => {} }).first.fetch('error')
# custom error for absolute keyword location
# instance: {}
# instance location: /abc
# formatted instance location: `/abc`
# keyword value: ["xyz"]
# keyword location: /properties/abc/required
# absolute keyword location: https://example.com/schema#/properties/abc/required
# details: {"missing_keys" => ["xyz"]}
# details__missing_keys: ["xyz"]
```

In the example above, custom error messsages are looked up using the following keys (in order until one is found):

1. `en.json_schemer.errors.'https://example.com/schema#/properties/abc/required'`
2. `en.json_schemer.errors.'https://example.com/schema'.'#/properties/abc/required'`
3. `en.json_schemer.errors.'#/properties/abc/required'`
4. `en.json_schemer.errors.'https://example.com/schema'.required`
5. `en.json_schemer.errors.'https://example.com/schema'.*`
6. `en.json_schemer.errors.'http://json-schema.org/draft-07/schema#'.required`
7. `en.json_schemer.errors.'http://json-schema.org/draft-07/schema#'.*`
8. `en.json_schemer.errors.required`
9. `en.json_schemer.errors.*`

## OpenAPI

```ruby
document = JSONSchemer.openapi({
  'openapi' => '3.1.0',
  'info' => {
    'title' => 'example'
  },
  'components' => {
    'schemas' => {
      'example' => {
        'type' => 'integer'
      }
    }
  }
})

# document validation using meta schema

document.valid?
# => false

document.validate.to_a
# => [{"data"=>{"title"=>"example"},
#      "data_pointer"=>"/info",
#      "schema"=>{...info schema},
#      "schema_pointer"=>"/$defs/info",
#      "root_schema"=>{...meta schema},
#      "type"=>"required",
#      "details"=>{"missing_keys"=>["version"]}},
#     ...]

# data validation using schema by name (in `components/schemas`)

document.schema('example').valid?(1)
# => true

document.schema('example').valid?('one')
# => false

# data validation using schema by ref

document.ref('#/components/schemas/example').valid?(1)
# => true

document.ref('#/components/schemas/example').valid?('one')
# => false
```

## CLI

The `json_schemer` executable takes a JSON schema file as the first argument followed by one or more JSON data files to validate. If there are any validation errors, it outputs them and returns an error code.

Validation errors are output as single-line JSON objects. The `--errors` option can be used to limit the number of errors returned or prevent output entirely (and fail fast).

The schema or data can also be read from stdin using `-`.

```
% json_schemer --help
Usage:
  json_schemer [options] <schema> <data>...
  json_schemer [options] <schema> -
  json_schemer [options] - <data>...
  json_schemer -h | --help
  json_schemer --version

Options:
  -e, --errors MAX                 Maximum number of errors to output
                                   Use "0" to validate with no output
  -h, --help                       Show help
  -v, --version                    Show version
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

## Build Status

![CI](https://github.com/davishmcclurg/json_schemer/actions/workflows/ci.yml/badge.svg)
![JSON Schema Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fbowtie.report%2Fbadges%2Fruby-json_schemer%2Fsupported_versions.json)<br>
![Draft 2020-12](https://img.shields.io/endpoint?url=https%3A%2F%2Fbowtie.report%2Fbadges%2Fruby-json_schemer%2Fcompliance%2Fdraft2020-12.json)
![Draft 2019-09](https://img.shields.io/endpoint?url=https%3A%2F%2Fbowtie.report%2Fbadges%2Fruby-json_schemer%2Fcompliance%2Fdraft2019-09.json)
![Draft 7](https://img.shields.io/endpoint?url=https%3A%2F%2Fbowtie.report%2Fbadges%2Fruby-json_schemer%2Fcompliance%2Fdraft7.json)
![Draft 6](https://img.shields.io/endpoint?url=https%3A%2F%2Fbowtie.report%2Fbadges%2Fruby-json_schemer%2Fcompliance%2Fdraft6.json)
![Draft 4](https://img.shields.io/endpoint?url=https%3A%2F%2Fbowtie.report%2Fbadges%2Fruby-json_schemer%2Fcompliance%2Fdraft4.json)

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/davishmcclurg/json_schemer.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
