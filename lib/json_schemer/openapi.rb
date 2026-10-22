# frozen_string_literal: true
module JSONSchemer
  class OpenAPI
    def initialize(document, **options)
      @document = document

      version = document['openapi']
      case version
      when /\A3\.2\.\d+\z/
        @document_schema = JSONSchemer.openapi32_document
        meta_schema = document.fetch('jsonSchemaDialect') { OpenAPI32::BASE_URI.to_s }
        discriminator_mode = 'hint'
      when /\A3\.1\.\d+\z/
        @document_schema = JSONSchemer.openapi31_document
        meta_schema = document.fetch('jsonSchemaDialect') { OpenAPI31::BASE_URI.to_s }
        # "discriminator MUST NOT change the validation outcome of the schema" since 3.1.1
        discriminator_mode = version == '3.1.0' ? 'select' : 'hint'
      when /\A3\.0\.\d+\z/
        @document_schema = JSONSchemer.openapi30_document
        meta_schema = OpenAPI30::BASE_URI.to_s
        discriminator_mode = 'select'
      else
        raise UnsupportedOpenAPIVersion, version
      end

      @version = version[/\A\d+\.\d+/]
      @options = options
      @schema_options = { :meta_schema => meta_schema, :discriminator_mode => discriminator_mode }.merge(options)
      @schema = JSONSchemer.schema(@document, **@schema_options)
    end

    # With `deep: true`, references are resolved and the documents they lead to validated too (see
    # `OpenAPIDeepValidation`).
    def valid?(deep: false, max_documents: nil)
      return deep_validate(max_documents, 'flag').fetch('valid') if deep
      @document_schema.valid?(@document)
    end

    def validate(deep: false, max_documents: nil, **options)
      return deep_validate(max_documents, options.fetch(:output_format) { 'classic' }) if deep
      @document_schema.validate(@document, **options)
    end

    # Dialect of the document's Schema Objects (unless they say otherwise).
    def default_meta_schema
      @schema.meta_schema
    end

    # Definition of an object in the document schema of the version (eg `/$defs/parameter`).
    def document_definition(pointer)
      DOCUMENT_DEFINITIONS["#{@version}#{pointer}"] ||= case @version
      when '3.0'
        JSONSchemer.openapi30_document.ref("##{pointer}")
      when '3.1'
        JSONSchemer.openapi31_document.ref("#{OpenAPI31::Document::SCHEMA.fetch('$id')}##{pointer}")
      else
        JSONSchemer.openapi32_document.ref("#{OpenAPI32::Document::SCHEMA.fetch('$id')}##{pointer}")
      end
    end
    DOCUMENT_DEFINITIONS = {}
    private_constant :DOCUMENT_DEFINITIONS

    def ref(value)
      @schema.ref(value)
    end

    def schema(name)
      ref("#/components/schemas/#{name}")
    end

  private

    def deep_validate(max_documents, output_format)
      schema_options = @schema_options.reject { |key, _value| key == :base_uri || key == :ref_resolver }
      deep_validation = OpenAPIDeepValidation.new(
        self,
        @schema.ref_resolver,
        :version => @version,
        :document_schema => @document_schema,
        :schema_options => schema_options,
        :output_format => output_format,
        :max_documents => max_documents
      )
      deep_validation.call(@document, URI(@options.fetch(:base_uri) { JSONSchemer.configuration.base_uri }))
    end
  end
end
