if RUBY_ENGINE == 'ruby'
  require 'simplecov'

  SimpleCov.start do
    enable_coverage :branch
    enable_coverage_for_eval
    minimum_coverage line: 100, branch: 100
  end
end

$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "json_schemer"

require "minitest/autorun"

def fetch(location, limit = 10)
  raise if limit.zero?
  uri = URI(location)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == 'https'
  # ignore certificate verification to avoid errors with outdated CRL stores
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  response = http.get(uri.request_uri)
  case response
  when Net::HTTPSuccess
    response.body
  when Net::HTTPRedirection
    fetch(URI.join(uri, response['Location']), limit - 1)
  else
    response.value.body
  end
end
