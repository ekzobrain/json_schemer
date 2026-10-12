# frozen_string_literal: true
module JSONSchemer
  module OpenAPI32
    module Vocab
      # https://spec.openapis.org/oas/v3.2.0#schema-object
      BASE = OpenAPI31::Vocab::BASE.merge(
        # https://spec.openapis.org/oas/v3.2.0#discriminator-object
        'discriminator' => Base::Discriminator
      )
    end
  end
end
