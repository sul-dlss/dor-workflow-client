# frozen_string_literal: true

require 'faraday'
require 'faraday_middleware'

module Dor
  module Workflow
    class Client
      # Builds Faraday connections that follow redirects
      class ConnectionFactory
        def self.build_connection(url, timeout:)
          Faraday.new(url: url) do |faraday|
            faraday.use Faraday::Response::RaiseError # raise exceptions on 40x, 50x responses
            faraday.use FaradayMiddleware::FollowRedirects, limit: 3
            faraday.adapter Faraday.default_adapter
            faraday.options.params_encoder = Faraday::FlatParamsEncoder
            if timeout
              faraday.options.timeout = timeout
              faraday.options.open_timeout = timeout
            end
            faraday.headers[:user_agent] = user_agent
          end
        end

        def self.user_agent
          "dor-workflow-service #{VERSION}"
        end
      end
    end
  end
end
