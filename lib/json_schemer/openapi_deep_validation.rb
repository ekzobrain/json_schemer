# frozen_string_literal: true
module JSONSchemer
  # Validates an OpenAPI description with everything it references (`OpenAPI#validate(deep: true)`): the root document
  # against the document schema of its version, then every Reference Object resolved (relative to the document it's
  # written in) and its target validated against the definition of the object expected at its position, and every
  # Schema Object validated against its dialect with its references resolved, through every document they lead to.
  class OpenAPIDeepValidation < DeepValidation
    OPERATIONS = ['get', 'put', 'post', 'delete', 'options', 'head', 'patch', 'trace'].freeze
    PARAMETER_CHILDREN = [['schema', :one, 'Schema'], ['content', :map, 'MediaType'], ['examples', :map, 'Example']].freeze
    ENCODING_CHILDREN = [
      ['encoding', :map, 'Encoding', '3.2'],
      ['prefixEncoding', :array, 'Encoding', '3.2'],
      ['itemEncoding', :one, 'Encoding', '3.2']
    ].freeze
    # members of each kind of object that hold other objects (and may be references): [member, :one/:map/:array, kind,
    # minimum version]; a nil member is every member (Callback)
    CHILDREN = {
      'OpenAPI' => [['paths', :map, 'PathItem'], ['webhooks', :map, 'PathItem', '3.1'], ['components', :one, 'Components']],
      'Components' => [
        ['schemas', :map, 'Schema'],
        ['responses', :map, 'Response'],
        ['parameters', :map, 'Parameter'],
        ['examples', :map, 'Example'],
        ['requestBodies', :map, 'RequestBody'],
        ['headers', :map, 'Header'],
        ['securitySchemes', :map, 'SecurityScheme'],
        ['links', :map, 'Link'],
        ['callbacks', :map, 'Callback'],
        ['pathItems', :map, 'PathItem', '3.1'],
        ['mediaTypes', :map, 'MediaType', '3.2']
      ],
      'PathItem' => [
        *OPERATIONS.map { |operation| [operation, :one, 'Operation'] },
        ['query', :one, 'Operation', '3.2'],
        ['additionalOperations', :map, 'Operation', '3.2'],
        ['parameters', :array, 'Parameter']
      ],
      'Operation' => [
        ['parameters', :array, 'Parameter'],
        ['requestBody', :one, 'RequestBody'],
        ['responses', :map, 'Response'],
        ['callbacks', :map, 'Callback']
      ],
      'Callback' => [[nil, :map, 'PathItem']],
      'Parameter' => PARAMETER_CHILDREN,
      'Header' => PARAMETER_CHILDREN,
      'RequestBody' => [['content', :map, 'MediaType']],
      'Response' => [['headers', :map, 'Header'], ['content', :map, 'MediaType'], ['links', :map, 'Link']],
      'MediaType' => [
        ['schema', :one, 'Schema'],
        ['itemSchema', :one, 'Schema', '3.2'],
        ['examples', :map, 'Example'],
        ['encoding', :map, 'Encoding'],
        ['prefixEncoding', :array, 'Encoding', '3.2'],
        ['itemEncoding', :one, 'Encoding', '3.2']
      ],
      'Encoding' => [['headers', :map, 'Header'], *ENCODING_CHILDREN],
      'Example' => [],
      'Link' => [],
      'SecurityScheme' => []
    }.freeze
    # kinds that can't be Reference Objects (a Path Item's `$ref` is followed with its other members)
    NOT_REFERABLE = ['OpenAPI', 'Components', 'Operation', 'Encoding'].freeze
    DEFINITIONS_30 = {
      'Components' => 'Components',
      'PathItem' => 'PathItem',
      'Operation' => 'Operation',
      'Callback' => 'Callback',
      'Parameter' => 'Parameter',
      'Header' => 'Header',
      'RequestBody' => 'RequestBody',
      'Response' => 'Response',
      'MediaType' => 'MediaType',
      'Encoding' => 'Encoding',
      'Example' => 'Example',
      'Link' => 'Link',
      'SecurityScheme' => 'SecurityScheme'
    }.freeze
    DEFINITIONS_31 = {
      'Components' => 'components',
      'PathItem' => 'path-item',
      'Operation' => 'operation',
      'Callback' => 'callbacks',
      'Parameter' => 'parameter',
      'Header' => 'header',
      'RequestBody' => 'request-body',
      'Response' => 'response',
      'MediaType' => 'media-type',
      'Encoding' => 'encoding',
      'Example' => 'example',
      'Link' => 'link',
      'SecurityScheme' => 'security-scheme'
    }.freeze
    # values that aren't schemas or OpenAPI objects (skipped when looking for references and identifiers)
    VALUE_KEYWORDS = ['example', 'examples', 'const', 'enum', 'default'].freeze
    SCHEMA_NAME_REGEX = /\A[a-zA-Z0-9.\-_]+\z/
    # characters of a JSON pointer encoded in a URI fragment (`+` too, decoded as a space by `Schema#resolve_ref`)
    POINTER_ENCODE_REGEX = /[^\w?\/:@\-.~!$&'()*,;=]/

    # Resolver that knows the identifiers (`$id`) declared in the documents already retrieved: an identifier wins over a
    # retrieval URL.
    class IndexedResolver < Resolver
      def initialize(*)
        super
        @index = {}
      end

      attr_reader :index

      def call(uri)
        @index.fetch(uri.to_s) { super }
      end
    end

    def initialize(openapi, ref_resolver, version:, document_schema:, schema_options:, **options)
      super(ref_resolver, **options)
      @resolver = IndexedResolver.new(ref_resolver, options[:max_documents]) unless version == '3.0'
      @openapi = openapi
      @version = version
      @document_schema = document_schema
      @schema_options = schema_options
      @values = {}
      @documents = {}
      @compiled = {}
      @visited = {}
      # documents' `$self` URIs (3.2) to the URIs they were retrieved from
      @aliases = {}
      # identifiers (3.1+) to the document and pointer declaring them
      @identifiers = {}
    end

    def call(document, base_uri)
      root_uri = document_uri(base_uri)
      @root_uri = root_uri
      @values[root_uri] = document
      @documents[root_uri] = document
      add_alias(root_uri)
      validate_document(document, root_uri, @document_schema)
      index_identifiers(root_uri) unless @version == '3.0'
      visit('OpenAPI', root_uri, '', :root)
      output
    end

  private

    def version?(minimum)
      minimum.nil? || @version >= minimum
    end

    # Visits the value at `pointer` in a document, expected to be an object of `kind`. `covered` says whether it was
    # validated already: as part of the root document (`:root`) or of an object validated against its definition
    # (`:definition`, which doesn't validate the Schema Objects in it against their dialect in 3.1+).
    def visit(kind, uri, pointer, covered)
      key = [kind, uri, pointer]
      return if @visited.key?(key)
      @visited[key] = true
      value = value_at(@documents.fetch(uri), pointer)

      return visit_schema(uri, pointer, value, covered) if kind == 'Schema'

      if value.is_a?(Hash) && value['$ref'].is_a?(String) && !NOT_REFERABLE.include?(kind)
        follow_reference(kind, uri, pointer, value.fetch('$ref'))
        # a Path Item's other members are its own
        return unless kind == 'PathItem'
      end

      unless covered
        definition = definition(kind)
        validate_document(value, uri, definition.fetch(:schema), pointer, kind, definition.fetch(:pointer))
        covered = :definition
      end
      return unless value.is_a?(Hash)

      CHILDREN.fetch(kind).each do |member, mode, child_kind, minimum_version|
        next unless version?(minimum_version)
        if member.nil?
          children = value
          member_pointer = pointer
        else
          children = value[member]
          member_pointer = "#{pointer}/#{Location.escape_json_pointer_token(member)}"
        end
        case mode
        when :one
          visit(child_kind, uri, member_pointer, covered) unless children.nil?
        when :map
          next unless children.is_a?(Hash)
          children.each_key do |name|
            next if name.start_with?('x-') || name == '$ref'
            visit(child_kind, uri, "#{member_pointer}/#{Location.escape_json_pointer_token(name)}", covered)
          end
        else
          next unless children.is_a?(Array)
          children.each_index { |index| visit(child_kind, uri, "#{member_pointer}/#{index}", covered) }
        end
      end
    end

    # Resolves a Reference Object (or a Path Item's `$ref`) and visits its target.
    def follow_reference(kind, uri, pointer, ref)
      resolved = resolve(uri, ref)
      return reference_error(uri, "#{pointer}/$ref", resolved, kind) if resolved.key?(:error)
      visit(kind, *resolved.fetch(:target), nil)
    end

    # Resolves a reference written in a document: `:target` is the document retrieved and a JSON pointer existing in
    # it, else `:error` says why it can't be resolved. `:ref` describes the reference.
    def resolve(uri, ref)
      ref_info = { 'value' => ref }
      begin
        ref_uri = URI.join(document_base_uri(uri), ref)
      rescue StandardError => e
        return { :error => "has an invalid reference `#{ref}`: #{e.message}", :ref => ref_info }
      end
      ref_info['uri'] = ref_uri.to_s
      target_uri = document_uri(ref_uri)
      target_uri = @aliases.fetch(target_uri, target_uri)
      fragment = ref_uri.fragment || ''
      unless fragment.empty? || Format.valid_json_pointer?(fragment)
        return { :error => "references `#{ref}`, whose fragment isn't a JSON pointer", :ref => ref_info }
      end
      document = document(target_uri)
      if document.is_a?(StandardError)
        return { :error => "references `#{ref}`, which can't be retrieved: #{document.message}", :ref => ref_info }
      end
      target_pointer = URI::DEFAULT_PARSER.unescape(fragment)
      unless pointer_exists?(document, target_pointer)
        return { :error => "references `#{ref}`, but pointer `#{target_pointer}` doesn't exist in `#{target_uri}`", :ref => ref_info }
      end
      { :target => [target_uri, target_pointer], :ref => ref_info }
    end

    def reference_error(uri, pointer, resolved, expected)
      add_error(uri, pointer, resolved.fetch(:error), 'ref', resolved.fetch(:ref), expected)
    end

    # Validates a Schema Object against its dialect (unless validated already) and resolves its references and the
    # references of its `discriminator` mappings.
    def visit_schema(uri, pointer, value, covered)
      if covered.nil? || (covered == :definition && @version != '3.0')
        if @version == '3.0'
          # the Schema Object definition of the document schema, as for the root document; a Reference Object (whose
          # other members are ignored) is followed below
          unless value.is_a?(Hash) && value.key?('$ref')
            definition = @openapi.document_definition('/definitions/Schema')
            return unless validate_document(value, uri, definition, pointer, 'Schema', '/definitions/Schema')
          end
        else
          begin
            meta_schema = schema_meta_schema(uri, value)
          rescue StandardError => e
            add_error(uri, pointer, "has an unknown meta schema: #{e.message}", 'schema', nil, 'Schema')
            return
          end
          return unless validate_document(value, uri, meta_schema, pointer, 'Schema')
        end
      end

      schema = compiled_document(uri)
      return add_error(uri, '', "schema can't be compiled: #{schema.message}", 'compile', nil, 'Schema') if schema.is_a?(StandardError)
      begin
        schema = schema.ref("##{Format.percent_encode(pointer, POINTER_ENCODE_REGEX)}")
      rescue StandardError => e
        add_error(uri, pointer, "schema can't be compiled: #{e.message}", 'compile', nil, 'Schema')
        return
      end
      walk_schema(schema, uri)
    end

    def walk_schema(schema, uri)
      values = [schema]
      while value = values.shift
        case value
        when Schema
          values << value.parsed
        when Keyword
          if value.respond_to?(:ref_uri) && value.respond_to?(:ref_schema)
            check_schema_ref(value, uri)
          else
            check_discriminator(value, uri) if value.keyword == 'discriminator'
            values << value.parsed
          end
        when Hash
          values.concat(value.values)
        when Array
          values.concat(value)
        end
      end
    end

    def check_schema_ref(keyword, uri)
      pointer = keyword.schema_pointer
      ref_info = { 'value' => keyword.value }
      begin
        ref_uri = keyword.ref_uri
      rescue StandardError => e
        add_error(uri, pointer, "has an invalid reference `#{keyword.value}`: #{e.message}", 'ref', ref_info, 'Schema')
        return
      end
      ref_info['uri'] = ref_uri.to_s
      target_uri = document_uri(ref_uri)
      target_uri = @aliases.fetch(target_uri, target_uri)
      unless local_resource?(keyword.root, target_uri)
        document = document(target_uri)
        if document.is_a?(StandardError)
          add_error(uri, pointer, "references `#{keyword.value}`, which can't be retrieved: #{document.message}", 'ref', ref_info, 'Schema')
          return
        end
      end
      begin
        ref_schema = keyword.ref_schema
      rescue InvalidRefPointer => e
        add_error(uri, pointer, "references `#{keyword.value}`, but pointer `#{e.message}` doesn't exist in `#{target_uri}`", 'ref', ref_info, 'Schema')
        return
      rescue InvalidRefResolution, UnknownRef => e
        # the target missing, or another document needed to compile it (eg its meta schema)
        message = e.message.start_with?(target_uri) ? "which doesn't exist in `#{target_uri}`" : "which can't be resolved: `#{e.message}` can't be retrieved"
        add_error(uri, pointer, "references `#{keyword.value}`, #{message}", 'ref', ref_info, 'Schema')
        return
      rescue KeyError
        add_error(uri, pointer, "references `#{keyword.value}`, which doesn't exist in `#{target_uri}`", 'ref', ref_info, 'Schema')
        return
      rescue StandardError => e
        add_error(uri, pointer, "references `#{keyword.value}`, which can't be resolved: #{e.message}", 'ref', ref_info, 'Schema')
        return
      end
      # the target's document: the referring one, the one declaring the identifier, or the one retrieved
      if ref_schema.root.equal?(keyword.root)
        visit('Schema', uri, ref_schema.schema_pointer, nil)
      elsif (location = @identifiers[target_uri])
        visit('Schema', location.fetch(0), "#{location.fetch(1)}#{ref_schema.schema_pointer}", nil)
      else
        visit('Schema', target_uri, ref_schema.schema_pointer, nil)
      end
    end

    # `discriminator` mapping values that are references (schema names are components of the entry document).
    def check_discriminator(keyword, uri)
      mapping = keyword.value.is_a?(Hash) && keyword.value['mapping']
      return unless mapping.is_a?(Hash)
      mapping.each do |name, value|
        next unless value.is_a?(String)
        mapping_pointer = "#{keyword.schema_pointer}/mapping/#{Location.escape_json_pointer_token(name)}"
        if SCHEMA_NAME_REGEX.match?(value)
          # a schema name (preferred) or else a URI reference; the name's error if neither resolves
          resolved = resolve(uri, "#{@root_uri}#/components/schemas/#{value}")
          if resolved.key?(:error)
            by_uri = resolve(uri, value)
            resolved = by_uri unless by_uri.key?(:error)
          end
        else
          resolved = resolve(uri, value)
        end
        if resolved.key?(:error)
          reference_error(uri, mapping_pointer, resolved, 'Schema')
        else
          visit('Schema', *resolved.fetch(:target), nil)
        end
      end
    end

    # Document retrieved at `uri` (once), or the error retrieving it.
    def document(uri)
      document = @documents[uri]
      return document if document && !document.is_a?(StandardError)
      # an identifier found since the first attempt
      return @documents[uri] = resolver.index.fetch(uri) if @version != '3.0' && resolver.index.key?(uri)
      return document if document
      @documents[uri] = begin
        resolver.call(URI(uri)) || raise(InvalidRefResolution, 'not found')
      rescue StandardError => e
        e
      end
      unless @documents[uri].is_a?(StandardError)
        add_alias(uri)
        index_identifiers(uri) unless @version == '3.0'
      end
      @documents[uri]
    end

    # 3.2: a document is known by its `$self` too.
    def add_alias(uri)
      self_uri = document_uri(document_base_uri(uri))
      return if self_uri == uri
      @aliases[self_uri] = uri
      @documents[self_uri] ||= @documents.fetch(uri)
    end

    # 3.1+: retrieves every document reachable by reference (as far as references can be told from the raw documents)
    # and indexes the identifiers declared in them, so that references to identifiers are resolved whatever the order.
    def index_identifiers(uri)
      documents = []
      scan(@documents.fetch(uri), document_base_uri(uri), '') do |kind, target, value, pointer|
        if kind == :id
          unless resolver.index.key?(target.to_s)
            resolver.index[target.to_s] = value
            @identifiers[target.to_s] = [uri, pointer]
          end
        else
          documents << target
        end
      end
      documents.each do |target|
        target_uri = target.dup
        target_uri.fragment = nil
        document(target_uri.to_s) unless @documents.key?(target_uri.to_s)
      end
    end

    def scan(value, base_uri, pointer, &block)
      case value
      when Hash
        id = value['$id']
        if id.is_a?(String)
          begin
            base_uri = URI.join(base_uri, id)
            resource_uri = base_uri.dup
            resource_uri.fragment = nil
            yield :id, resource_uri, value, pointer
          rescue URI::Error
            # invalid `$id`, reported by the meta schema
          end
        end
        ref = value['$ref']
        if ref.is_a?(String)
          begin
            yield :ref, URI.join(base_uri, ref)
          rescue URI::Error
            # invalid reference, reported when it's resolved
          end
        end
        value.each do |key, nested|
          next if VALUE_KEYWORDS.include?(key) || key.start_with?('x-')
          scan(nested, base_uri, "#{pointer}/#{Location.escape_json_pointer_token(key)}", &block)
        end
      when Array
        value.each_with_index { |nested, index| scan(nested, base_uri, "#{pointer}/#{index}", &block) }
      end
    end

    # Base URI of a document: its `$self` (3.2), else the URI it was retrieved from.
    def document_base_uri(uri)
      document = @documents[uri]
      self_uri = @version >= '3.2' && document.is_a?(Hash) && document['$self']
      self_uri.is_a?(String) ? URI.join(uri, self_uri) : URI(uri)
    rescue URI::Error
      URI(uri)
    end

    # A document compiled as a schema (once), to resolve the references of its Schema Objects, or the compile error.
    def compiled_document(uri)
      @compiled.fetch(uri) do
        @compiled[uri] = begin
          JSONSchemer.schema(
            @documents.fetch(uri),
            **@schema_options,
            :base_uri => document_base_uri(uri),
            :ref_resolver => resolver
          )
        rescue StandardError => e
          e
        end
      end
    end

    # 3.1+ dialect of a Schema Object: its `$schema`, its document's (a schema of its own), else the document's default
    # (`jsonSchemaDialect` or the OAS dialect).
    def schema_meta_schema(uri, value)
      document = @documents.fetch(uri)
      dialect = (value.is_a?(Hash) && value['$schema']) || (document.is_a?(Hash) && document['$schema'])
      return @openapi.default_meta_schema unless dialect.is_a?(String)
      META_SCHEMAS_BY_BASE_URI_STR[dialect] || JSONSchemer.schema({ '$schema' => dialect }, :ref_resolver => resolver).meta_schema
    end

    def definition(kind)
      if @version == '3.0'
        name = DEFINITIONS_30.fetch(kind)
        pointer = "/definitions/#{name}"
      else
        name = DEFINITIONS_31.fetch(kind)
        pointer = "/$defs/#{name}"
      end
      { :schema => @openapi.document_definition(pointer), :pointer => pointer }
    end
  end
end
