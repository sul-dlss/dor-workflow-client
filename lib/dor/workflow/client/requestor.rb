# frozen_string_literal: true

module Dor
  module Workflow
    class Client
      # Makes requests to the workflow service and retries them if necessary.
      class Requestor
        def initialize(connection:)
          @connection = connection
        end

        attr_reader :connection

        # calls workflow_resource[uri_string]."#{meth}" with variable number of optional arguments
        # The point of this is to wrap ALL remote calls with consistent error handling and logging
        # @param [String] uri_string resource to request
        # @param [String] meth REST method to use on resource (get, put, post, delete, etc.)
        # @param [String] payload body for (e.g. put) request
        # @param [Hash] opts addtional headers options
        # @return [Object] response from method
        # @raise [Dor::WorkflowException,Dor::MissingWorkflowException] if there are Faraday exceptions
        def request(uri_string, meth = 'get', payload = '', opts = {})
          response = send_workflow_resource_request(uri_string, meth, payload, opts)
          response.body
        rescue Faraday::Error => e
          # `status` is set to `nil` if:
          # * `e` does not respond to `:response`
          # * `e` responds to `:response` and:
          #   * `e.response` is `nil`
          #   * `e.response` is a hash missing the `:status` key
          # else it is set to the value of `e.response[:status]`
          status = e.try(:response)&.fetch(:status, nil)
          msg = "Failed to retrieve resource: #{meth} #{base_url}/#{uri_string}"
          msg += " (HTTP status #{status})" unless status.nil?
          raise (status == 404 ? Dor::MissingWorkflowException : Dor::WorkflowException), msg
        end

        private

        ##
        # Get the configured URL for the connection
        def base_url
          connection.url_prefix
        end

        def send_workflow_resource_request(uri_string, meth = 'get', payload = '', opts = {})
          connection.public_send(meth, uri_string) do |req|
            req.body = payload unless meth == 'delete'
            req.params.update opts[:params] if opts[:params]
            req.headers.update opts.except(:params)
          end
        end
      end
    end
  end
end
