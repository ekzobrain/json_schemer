# frozen_string_literal: true
module JSONSchemer
  class Keyword
    include Output

    attr_reader :value, :parent, :root, :parsed

    def initialize(value, parent, keyword, schema = parent)
      @value = value
      @parent = parent
      @root = parent.root
      @keyword = keyword
      @schema = schema
      @parsed = parse
    end

    def validate(_instance, _instance_location, _keyword_location, _context)
      nil
    end

    def valid_instance?(_instance, _context)
      nil
    end

    def absolute_keyword_location
      @absolute_keyword_location ||= "#{parent.absolute_keyword_location}/#{fragment_encode(escaped_keyword)}"
    end

    def schema_pointer
      @schema_pointer ||= "#{parent.schema_pointer}/#{escaped_keyword}"
    end

    def error_key
      keyword
    end

    def fetch(key)
      parsed.fetch(parsed.is_a?(Array) ? key.to_i : key)
    end

    def parsed_schema
      parsed.is_a?(Schema) ? parsed : nil
    end

  private

    def parse
      value
    end

    def subschema(value, keyword = nil, **options)
      options[:configuration] ||= schema.configuration
      options[:base_uri] ||= schema.base_uri
      options[:meta_schema] ||= schema.meta_schema
      options[:ref_resolver] ||= schema.ref_resolver
      options[:regexp_resolver] ||= schema.regexp_resolver
      Schema.new(value, self, root, keyword, **options)
    end

    # Object in the caller's data at `instance_location`, which hooks modify. With `stringified_keys` the validated
    # instance is the caller's data itself, otherwise it is a key-stringified copy that must be looked up. Instances
    # that aren't part of the caller's data (`detached`, eg decoded `contentSchema` content) are used as is.
    def caller_instance(instance, instance_location, context)
      context.stringified_keys || context.detached ? instance : context.original_instance(instance_location)
    end

    # Brings the validated instance in line with changes made to the caller's data.
    def sync_instance(instance, original_instance, context)
      instance.replace(deep_stringify_keys(original_instance)) unless context.stringified_keys || context.detached
    end

    # Calls a hook with as many arguments as it accepts, so lambdas and methods can take fewer. Procs ignore extra
    # arguments themselves.
    def call_hook(hook, *args)
      strict = !hook.is_a?(Proc) || hook.lambda?
      count = hook_parameter_count(hook)
      strict && count && count < args.size ? hook.call(*args.first(count)) : hook.call(*args)
    end

    # Number of arguments a hook declares, or nil if it takes any number.
    def hook_parameter_count(hook)
      (@hook_parameter_counts ||= {}.compare_by_identity).fetch(hook) do
        @hook_parameter_counts[hook] = if hook.respond_to?(:parameters)
          parameters = hook.parameters
          parameters.count { |type, _name| type == :req || type == :opt } unless parameters.any? { |type, _name| type == :rest }
        end
      end
    end

    # Caller's object/array whose values are validated, for value hooks (`before_value_validation`,
    # `after_value_validation`, `deferred_value_validation`), or nil when there are none.
    def value_hooks_data(instance, instance_location, context)
      caller_instance(instance, instance_location, context) if root.value_hooks?
    end

    # Calls value hooks around validating the value at `key` of `instance` with `subschema` (the block). `data` is
    # from `value_hooks_data`.
    def validate_value(data, instance, key, subschema, instance_location, context)
      return yield unless data

      location = Location.resolve(instance_location)
      # recorded in the current transaction (eg of a `contains` item), so that changes are rolled back with it
      if root.before_value_validation.any? || root.after_value_validation.any?
        context.record_change(data)
        context.record_change(instance)
      end

      if (hooks = root.before_value_validation).any?
        hooks.each { |hook| call_hook(hook, data, key, subschema, schema, location) }
        sync_instance(instance, data, context)
      end

      nested_result = yield

      if (hooks = root.after_value_validation).any?
        hooks.each { |hook| call_hook(hook, data, key, subschema, schema, location) }
        sync_instance(instance, data, context)
      end

      if (hooks = root.deferred_value_validation).any?
        context.defer do
          hooks.each { |hook| call_hook(hook, data, key, subschema, schema, location) }
        end
      end

      nested_result
    end

  end
end
