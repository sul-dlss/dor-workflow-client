# frozen_string_literal: true

module Dor
  module Workflow
    class Client
      # Builds Faraday connections that follow redirects
      class ConnectionFactory
        def self.build_connection(url, timeout:, logger:)
          new(url, timeout: timeout, logger: logger).build_connection
        end

        def initialize(url, timeout:, logger:)
          @url = url
          @timeout = timeout
          @logger = logger
        end

        # rubocop:disable Metrics/MethodLength
        def build_connection
          Faraday.new(url: url) do |faraday|
            faraday.use Faraday::Response::RaiseError # raise exceptions on 40x, 50x responses
            faraday.options.params_encoder = Faraday::FlatParamsEncoder
            if timeout
              faraday.options.timeout = timeout
              faraday.options.open_timeout = timeout
            end
            faraday.headers[:user_agent] = user_agent
            faraday.request :retry,
                            max: 2,
                            interval: 5.0,
                            interval_randomness: 0.01,
                            backoff_factor: 2.0,
                            methods: retriable_methods,
                            exceptions: retriable_exceptions,
                            retry_block: retry_block,
                            retry_statuses: retry_statuses
            faraday.adapter Faraday.default_adapter # Last middleware must be the adapter
          end
        end
        # rubocop:enable Metrics/MethodLength

        def user_agent
          "dor-workflow-client #{VERSION}"
        end

        private

        attr_reader :logger, :timeout, :url

        def retriable_methods
          Faraday::Retry::Middleware::IDEMPOTENT_METHODS + [:post]
        end

        def retriable_exceptions
          Faraday::Retry::Middleware::DEFAULT_EXCEPTIONS + [Faraday::ConnectionFailed]
        end

        def retry_block
          lambda do |env, _opts, retries, exception|
            logger.warn "retrying connection (#{retries} remaining) to #{env.url}: (#{exception.class}) " \
                        "#{exception.message} #{env.status}"
          end
        end

        def retry_statuses
          [429, 500, 502, 503, 504, 599]
        end
      end
    end
  end
end
