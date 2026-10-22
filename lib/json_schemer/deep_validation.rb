# frozen_string_literal: true
module JSONSchemer
  # Validates a schema with everything it references (`deep: true` of `validate_schema`/`valid_schema?`): the schema
  # against its meta schema, every reference (`$ref`, `$dynamicRef`, `$recursiveRef`) resolved, and every document
  # loaded through `ref_resolver` against its own meta schema, with its references in turn. Unresolvable references are
  # validation errors rather than exceptions, and every error says which document it is in.
  class DeepValidation
    OUTPUT_FORMATS = ['flag', 'basic', 'classic'].freeze

    class DocumentLimitReached < StandardError; end

    # `ref_resolver` caching documents (and errors) for one validation, so that a document is retrieved once whether
    # it's validated, compiled or referenced again, and counting them for `max_documents`.
    class Resolver
      def initialize(resolver, max_documents)
        @resolver = resolver
        @max_documents = max_documents
        @documents = {}
      end

      def call(uri)
        key = uri.to_s
        unless @documents.key?(key)
          @documents[key] = begin
            raise DocumentLimitReached, "more than #{@max_documents} documents referenced" if @max_documents && @documents.size >= @max_documents
            @resolver.call(uri)
          rescue StandardError => e
            e
          end
        end
        document = @documents.fetch(key)
        raise document if document.is_a?(StandardError)
        document
      end
    end

    attr_reader :output_format, :resolver

    def initialize(ref_resolver, output_format: 'classic', max_documents: nil)
      raise UnknownOutputFormat, output_format unless OUTPUT_FORMATS.include?(output_format)
      @output_format = output_format
      @resolver = Resolver.new(ref_resolver, max_documents)
      @valid = true
      @errors = []
      # retrieved documents by URI: `true` (valid), `false` (invalid against its meta schema) or the error retrieving it
      @documents = {}
      @values = {}
      @walked = {}
    end

    # Validates `value` (a schema document identified by `base_uri`) against its meta schema (returned by
    # `meta_schema`) and then everything it references. The block returns the schema compiled with `resolver`.
    def call(value, base_uri, meta_schema)
      document_uri = document_uri(base_uri)
      begin
        meta_schema = meta_schema.call
      rescue StandardError => e
        add_error(document_uri, '', "has an unknown meta schema: #{e.message}", 'schema')
        return output
      end
      if validate_document(value, document_uri, meta_schema)
        begin
          schema = yield
        rescue StandardError => e
          add_error(document_uri, '', "schema can't be compiled: #{e.message}", 'compile')
        end
        walk(schema, document_uri) if schema
      end
      output
    end

    def output
      # the same value can be validated more than once (eg reached by references and by its position)
      errors = @errors.uniq { |error| [error[output_format == 'basic' ? 'absoluteInstanceLocation' : 'data_uri'], error['error']] }
      case output_format
      when 'flag'
        { 'valid' => @valid }
      when 'basic'
        { 'valid' => @valid, 'errors' => errors }
      else
        errors
      end
    end

    # Validates a document (or the part of it at `pointer`) against a (meta) schema, adding its errors, located in the
    # document. `expected` is added to the errors (eg the kind of OpenAPI object) and `keyword_prefix` to their keyword
    # locations. Returns whether it's valid.
    def validate_document(value, document_uri, meta_schema, pointer = '', expected = nil, keyword_prefix = '')
      if output_format == 'flag'
        valid = meta_schema.valid?(value)
      else
        output = meta_schema.validate_located(value, pointer, output_format)
        errors = output_format == 'basic' ? (output['errors'] || []).to_a : output.to_a
        errors.each do |error|
          error['keywordLocation'] = "#{keyword_prefix}#{error.fetch('keywordLocation')}" if output_format == 'basic'
          error['expected'] = expected if expected
          @errors << locate(error, document_uri)
        end
        valid = output_format == 'basic' ? output.fetch('valid') : errors.empty?
      end
      @valid &&= valid
      valid
    end

    # Adds an error (eg an unresolvable reference) at `pointer` in a document.
    def add_error(document_uri, pointer, message, type, ref = nil, expected = nil)
      @valid = false
      return if output_format == 'flag'
      formatted_location = pointer.empty? ? 'root' : "`#{pointer}`"
      error = if output_format == 'basic'
        {
          'valid' => false,
          'keywordLocation' => '',
          'instanceLocation' => pointer,
          'error' => "value at #{formatted_location} #{message}"
        }
      else
        {
          'data_pointer' => pointer,
          'type' => type,
          'error' => "value at #{formatted_location} #{message}"
        }
      end
      error['ref'] = ref if ref
      error['expected'] = expected if expected
      @errors << locate(error, document_uri)
    end

    # Walks the references of a compiled schema (and of the documents they lead to).
    def walk(schema, document_uri)
      return if @walked.key?(document_uri)
      @walked[document_uri] = true
      values = [schema]
      while value = values.shift
        case value
        when Schema
          values << value.parsed
        when Keyword
          if value.respond_to?(:ref_uri) && value.respond_to?(:ref_schema)
            check_ref(value, document_uri)
          else
            values << value.parsed
          end
        when Hash
          values.concat(value.values)
        when Array
          values.concat(value)
        end
      end
    end

    # Resolves a reference: its document is retrieved and validated (once), then the reference resolved in it and its
    # document walked.
    def check_ref(keyword, document_uri)
      pointer = keyword.schema_pointer
      ref = { 'value' => keyword.value }
      begin
        ref_uri = keyword.ref_uri
      rescue StandardError => e
        add_error(document_uri, pointer, "has an invalid reference `#{keyword.value}`: #{e.message}", 'ref', ref)
        return
      end
      ref['uri'] = ref_uri.to_s
      target_uri = ref_uri.dup
      target_uri.fragment = nil
      local = local_resource?(keyword.root, target_uri)

      unless local
        target = retrieve(target_uri, keyword.schema.meta_schema)
        if target == false
          # an invalid document isn't compiled, but a JSON pointer into it can still be checked
          fragment = ref_uri.fragment
          if fragment && Format.valid_json_pointer?(fragment) && !pointer_exists?(@values.fetch(target_uri.to_s), URI.decode_www_form_component(fragment))
            add_error(document_uri, pointer, "references `#{keyword.value}`, but pointer `#{URI.decode_www_form_component(fragment)}` doesn't exist in `#{target_uri}`", 'ref', ref)
          end
          return
        elsif target != true
          add_error(document_uri, pointer, "references `#{keyword.value}`, which can't be retrieved: #{target.message}", 'ref', ref)
          return
        end
      end

      begin
        ref_schema = keyword.ref_schema
      rescue InvalidRefPointer => e
        add_error(document_uri, pointer, "references `#{keyword.value}`, but pointer `#{e.message}` doesn't exist in `#{target_uri}`", 'ref', ref)
        return
      rescue InvalidRefResolution, UnknownRef => e
        # the target missing, or another document needed to compile it (eg its meta schema)
        message = e.message.start_with?(target_uri.to_s) ? "which doesn't exist in `#{target_uri}`" : "which can't be resolved: `#{e.message}` can't be retrieved"
        add_error(document_uri, pointer, "references `#{keyword.value}`, #{message}", 'ref', ref)
        return
      rescue KeyError
        add_error(document_uri, pointer, "references `#{keyword.value}`, which doesn't exist in `#{target_uri}`", 'ref', ref)
        return
      rescue StandardError => e
        add_error(document_uri, pointer, "references `#{keyword.value}`, which can't be resolved: #{e.message}", 'ref', ref)
        return
      end

      walk(ref_schema.root, target_uri.to_s) unless local
    end

    # Retrieves and validates a document (once): `true` when valid, `false` when invalid (errors added), else the error
    # retrieving it.
    def retrieve(uri, default_meta_schema)
      key = uri.to_s
      return @documents.fetch(key) if @documents.key?(key)
      value = begin
        @values[key] = resolver.call(uri) || raise(InvalidRefResolution, 'not found')
      rescue StandardError => e
        return @documents[key] = e
      end
      meta_schema = begin
        document_meta_schema(value, default_meta_schema)
      rescue StandardError => e
        add_error(key, '', "has an unknown meta schema: #{e.message}", 'schema')
        return @documents[key] = false
      end
      @documents[key] = validate_document(value, key, meta_schema)
    end

  private

    def document_uri(uri)
      document_uri = uri.dup
      document_uri.fragment = nil
      document_uri.to_s
    end

    def pointer_exists?(value, pointer)
      !value_at(value, pointer).equal?(MISSING)
    end

    MISSING = Object.new.freeze
    private_constant :MISSING

    # Value at a JSON pointer in a document, or `MISSING`.
    def value_at(value, pointer)
      Hana::Pointer.parse(pointer).reduce(value) do |current, token|
        case current
        when Hash
          return MISSING unless current.key?(token)
          current.fetch(token)
        when Array
          index = Integer(token, 10) rescue (return MISSING)
          return MISSING unless index >= 0 && index < current.size
          current.fetch(index)
        else
          return MISSING
        end
      end
    end

    def local_resource?(root, uri)
      lexical_resources = root.resources.fetch(:lexical)
      !!(lexical_resources[uri] || lexical_resources["#{uri}#"])
    end

    def document_meta_schema(value, default_meta_schema)
      meta_schema = value.is_a?(Hash) && (value['$schema'] || value[:'$schema'])
      return default_meta_schema unless meta_schema.is_a?(String)
      META_SCHEMAS_BY_BASE_URI_STR[meta_schema] || JSONSchemer.schema({ '$schema' => meta_schema }, :ref_resolver => resolver).meta_schema
    end

    def locate(error, document_uri)
      if output_format == 'basic'
        error['absoluteInstanceLocation'] = absolute_location(document_uri, error.fetch('instanceLocation'))
      else
        error['data_uri'] = absolute_location(document_uri, error.fetch('data_pointer'))
      end
      error
    end

    def absolute_location(document_uri, pointer)
      "#{document_uri}##{Format.percent_encode(pointer, Output::FRAGMENT_ENCODE_REGEX)}"
    end
  end
end
