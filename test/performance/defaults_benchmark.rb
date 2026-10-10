# frozen_string_literal: true

# Time, allocations and hook calls of inserting defaults into a 200 item order with `insert_property_defaults` (defaults
# are inserted after validation, then the instance is validated again) and with the `INSERT_PROPERTY_DEFAULT` hook in
# `before_object_validation` (defaults are inserted before validation, in a single pass). Both are run with data
# missing defaulted properties and with data that has them all, alone and with a no-op `before_property_validation`
# hook (counting its calls), and both must produce the same data.
#
#   ruby test/performance/defaults_benchmark.rb
#
# To compare with another revision, check it out (eg `git worktree add /tmp/base <rev>`) and run:
#
#   LIB_PATH=/tmp/base/lib BENCH_LABEL=base ruby test/performance/defaults_benchmark.rb
#
# Modes using options that a revision doesn't have are skipped. Times vary between runs (~15%); allocations are
# stable. Don't run it with `bundle exec`, which loads this checkout's `lib` before `LIB_PATH`.

$LOAD_PATH.unshift(ENV.fetch('LIB_PATH')) if ENV.key?('LIB_PATH')
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__)) unless ENV.key?('LIB_PATH')

require 'json'
require 'json_schemer'

ITERATIONS = Integer(ENV.fetch('ITERATIONS', '30'))
BENCH_LABEL = ENV.fetch('BENCH_LABEL', 'current')

SCHEMA = {
  'type' => 'object',
  'properties' => {
    'id' => { 'type' => 'integer' },
    'status' => { 'enum' => ['new', 'paid'], 'default' => 'new' },
    'customer' => {
      'type' => 'object',
      'properties' => {
        'name' => { 'type' => 'string' },
        'kind' => { 'enum' => ['person', 'company'], 'default' => 'person' }
      },
      'required' => ['name', 'kind']
    },
    'items' => {
      'type' => 'array',
      'items' => {
        'type' => 'object',
        'properties' => {
          'sku' => { 'type' => 'string' },
          'price' => { 'type' => 'number', 'minimum' => 0 },
          'quantity' => { 'type' => 'integer', 'minimum' => 1, 'default' => 1 },
          'tags' => { 'type' => 'array', 'items' => { 'type' => 'string' }, 'default' => [] },
          'gift' => { 'type' => 'boolean', 'default' => false }
        },
        'required' => ['sku', 'price', 'quantity']
      }
    }
  },
  'required' => ['id', 'status', 'customer', 'items']
}.freeze

DATA_JSON = {
  'missing defaults' => JSON.generate(
    'id' => 1,
    'customer' => { 'name' => 'Acme' },
    'items' => Array.new(200) { |index| { 'sku' => "ABC-#{index}", 'price' => index * 1.5 } }
  ),
  'all present' => JSON.generate(
    'id' => 1,
    'status' => 'paid',
    'customer' => { 'name' => 'Acme', 'kind' => 'company' },
    'items' => Array.new(200) { |index| { 'sku' => "ABC-#{index}", 'price' => index * 1.5, 'quantity' => 2, 'tags' => ['a'], 'gift' => true } }
  )
}.freeze

HOOK_CALLS = [0]
COUNTING_HOOK = proc { |_data, _property, _property_schema, _parent_schema| HOOK_CALLS[0] += 1 }

options = JSONSchemer::Configuration.members
insert_property_default = JSONSchemer::Schema.const_defined?(:INSERT_PROPERTY_DEFAULT) && options.include?(:before_object_validation)

MODES = {
  'insert_property_defaults' => { :insert_property_defaults => true },
  'insert_property_defaults + hook' => { :insert_property_defaults => true, :before_property_validation => [COUNTING_HOOK] }
}
if insert_property_default
  MODES['INSERT_PROPERTY_DEFAULT'] = { :before_object_validation => [JSONSchemer::Schema::INSERT_PROPERTY_DEFAULT] }
  MODES['INSERT_PROPERTY_DEFAULT + hook'] = MODES['INSERT_PROPERTY_DEFAULT'].merge(:before_property_validation => [COUNTING_HOOK])
end
MODES.freeze

def measure(copies)
  GC.start
  allocated = GC.stat(:total_allocated_objects)
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  copies.each { |data| yield data }
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  [elapsed / copies.size * 1000, (GC.stat(:total_allocated_objects) - allocated) / copies.size]
end

puts 'label,stringified_keys,data,mode,valid? ms,valid? objects,hook calls'
[false, true].each do |stringified_keys|
  next if stringified_keys && !options.include?(:stringified_keys)
  DATA_JSON.each do |data_name, data_json|
    results = {}
    MODES.each do |mode, mode_options|
      schemer = JSONSchemer.schema(SCHEMA, **mode_options, **(stringified_keys ? { :stringified_keys => true } : {}))
      3.times { schemer.valid?(JSON.parse(data_json)) }

      result = JSON.parse(data_json)
      HOOK_CALLS[0] = 0
      raise "invalid data (#{mode})" unless schemer.valid?(result)
      hook_calls = HOOK_CALLS[0]
      results[mode] = result

      copies = Array.new(ITERATIONS) { JSON.parse(data_json) }
      ms, objects = measure(copies) { |data| schemer.valid?(data) }
      puts [BENCH_LABEL, stringified_keys, data_name, mode, ms.round(2), objects, hook_calls].join(',')
    end
    raise "different data (#{data_name})" unless results.values.uniq.size == 1
  end
end
