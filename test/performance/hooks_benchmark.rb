# frozen_string_literal: true

# Time and allocations of validating a 200 item order without hooks and with no-op hooks, to check that hooks don't
# slow down validation when they're not used or are light.
#
#   ruby test/performance/hooks_benchmark.rb
#
# To compare with another revision, check it out (eg `git worktree add /tmp/base <rev>`) and run:
#
#   LIB_PATH=/tmp/base/lib BENCH_LABEL=base ruby test/performance/hooks_benchmark.rb
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
    'customer' => {
      'type' => 'object',
      'properties' => {
        'name' => { 'type' => 'string', 'minLength' => 1 },
        'email' => { 'type' => 'string', 'format' => 'email' },
        'kind' => { 'enum' => ['person', 'company'] }
      },
      'required' => ['name', 'kind']
    },
    'items' => {
      'type' => 'array',
      'items' => {
        'type' => 'object',
        'properties' => {
          'sku' => { 'type' => 'string', 'pattern' => '^[A-Z]{3}-\\d+$' },
          'price' => { 'type' => 'number', 'minimum' => 0 },
          'quantity' => { 'type' => 'integer', 'minimum' => 1 },
          'date' => { 'type' => 'string', 'format' => 'date' },
          'tags' => { 'type' => 'array', 'items' => { 'type' => 'string' } }
        },
        'required' => ['sku', 'price', 'quantity'],
        'oneOf' => [
          { 'properties' => { 'quantity' => { 'maximum' => 10 } } },
          { 'properties' => { 'quantity' => { 'minimum' => 11 } } }
        ],
        'additionalProperties' => false
      }
    }
  },
  'required' => ['id', 'customer', 'items']
}.freeze

DATA_JSON = JSON.generate(
  'id' => 1,
  'customer' => { 'name' => 'Acme', 'email' => 'a@example.com', 'kind' => 'company' },
  'items' => Array.new(200) do |index|
    { 'sku' => "ABC-#{index}", 'price' => index * 1.5, 'quantity' => (index % 20) + 1, 'date' => '2020-09-03', 'tags' => ['a', 'b', 'c'] }
  end
)

NOOP_4 = proc { |_data, _property, _property_schema, _parent_schema| }
NOOP_5 = proc { |_data, _key, _schema, _parent_schema, _location| }
ALL_HOOKS = [
  :before_object_validation,
  :before_property_validation,
  :before_value_validation,
  :after_value_validation,
  :after_property_validation,
  :deferred_value_validation
].freeze

MODES = {
  'no hooks' => {},
  'no-op property hooks' => { :before_property_validation => [NOOP_4], :after_property_validation => [NOOP_4] },
  'no-op all hooks' => ALL_HOOKS.to_h { |hook| [hook, [hook.to_s.include?('property_validation') ? NOOP_4 : NOOP_5]] },
  'no-op all hooks (4 params)' => ALL_HOOKS.to_h { |hook| [hook, [NOOP_4]] }
}.freeze

def measure
  GC.start
  allocated = GC.stat(:total_allocated_objects)
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  ITERATIONS.times { yield }
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  [elapsed / ITERATIONS * 1000, (GC.stat(:total_allocated_objects) - allocated) / ITERATIONS]
end

options = JSONSchemer::Configuration.members
puts 'label,stringified_keys,mode,valid? ms,valid? objects,basic ms,basic objects'
[false, true].each do |stringified_keys|
  next if stringified_keys && !options.include?(:stringified_keys)
  MODES.each do |mode, hooks|
    next unless hooks.keys.all? { |hook| options.include?(hook) }

    schemer = JSONSchemer.schema(SCHEMA, **hooks, **(stringified_keys ? { :stringified_keys => true } : {}))
    data = JSON.parse(DATA_JSON)
    raise "invalid data (#{mode})" unless schemer.valid?(data)
    3.times do
      schemer.valid?(data)
      schemer.validate(data, :output_format => 'basic')
    end

    valid_ms, valid_objects = measure { schemer.valid?(data) }
    basic_ms, basic_objects = measure { schemer.validate(data, :output_format => 'basic') }
    puts [BENCH_LABEL, stringified_keys, mode, valid_ms.round(2), valid_objects, basic_ms.round(2), basic_objects].join(',')
  end
end
