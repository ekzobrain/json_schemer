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

    # Brings the validated instance in line with changes made to the caller's data (nothing to do when the instance
    # is the caller's data, eg with `stringified_keys` or string keys).
    def sync_instance(instance, original_instance, context)
      return if context.stringified_keys || context.detached || instance.equal?(original_instance)
      instance.replace(deep_stringify_keys(original_instance))
    end

    # Calls a hook with `data, key, schema, parent_schema` and `location` (if given). Lambdas and methods only get
    # as many arguments as they declare; procs ignore extra arguments themselves.
    def call_hook(hook, data, key, schema, parent_schema, location = NO_LOCATION)
      size = NO_LOCATION.equal?(location) ? 4 : 5
      max = hook_max_arguments(hook)
      if max && max < size
        case max
        when 0 then hook.call
        when 1 then hook.call(data)
        when 2 then hook.call(data, key)
        when 3 then hook.call(data, key, schema)
        else hook.call(data, key, schema, parent_schema)
        end
      elsif size == 4
        hook.call(data, key, schema, parent_schema)
      else
        hook.call(data, key, schema, parent_schema, location)
      end
    end
    NO_LOCATION = Object.new.freeze
    private_constant :NO_LOCATION

    # Number of arguments a hook declares, or nil if it takes any number.
    def hook_parameter_count(hook)
      (@hook_parameter_counts ||= {}.compare_by_identity).fetch(hook) do
        @hook_parameter_counts[hook] = if hook.respond_to?(:parameters)
          parameters = hook.parameters
          parameters.count { |type, _name| type == :req || type == :opt } unless parameters.any? { |type, _name| type == :rest }
        end
      end
    end

    # Number of arguments a hook accepts (lambdas and methods), or nil if it accepts any number (procs, rest
    # parameters).
    def hook_max_arguments(hook)
      (@hook_max_arguments ||= {}.compare_by_identity).fetch(hook) do
        @hook_max_arguments[hook] = (hook_parameter_count(hook) unless hook.is_a?(Proc) && !hook.lambda?)
      end
    end

    # Whether any of the hooks may use the location argument (so it's only built when needed).
    def hooks_use_location?(hooks)
      (@hooks_use_location ||= {}.compare_by_identity).fetch(hooks) do
        @hooks_use_location[hooks] = hooks.any? { |hook| (count = hook_parameter_count(hook)).nil? || count >= 5 }
      end
    end

    def call_value_hooks(hooks, data, key, subschema, value_location)
      location = Location.resolve(value_location) if hooks_use_location?(hooks)
      hooks.each { |hook| call_hook(hook, data, key, subschema, schema, location) }
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

      # the same location object is used to validate the value
      value_location = Location.join(instance_location, key.to_s)
      before_hooks = root.before_value_validation
      after_hooks = root.after_value_validation

      # recorded in the current transaction (eg of a `contains` item), so that changes are rolled back with it
      if before_hooks.any? || after_hooks.any?
        context.record_change(data)
        context.record_change(instance)
      end

      if before_hooks.any?
        call_value_hooks(before_hooks, data, key, subschema, value_location)
        sync_instance(instance, data, context)
      end

      nested_result = yield

      if after_hooks.any?
        call_value_hooks(after_hooks, data, key, subschema, value_location)
        sync_instance(instance, data, context)
      end

      context.defer([self, data, key, subschema, value_location]) if root.deferred_value_validation.any?

      nested_result
    end

  end
end
