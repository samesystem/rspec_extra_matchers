# frozen_string_literal: true

require 'active_support/core_ext/string/indent'

require_relative 'type_matcher'

module RSpecExtraMatchers
  module GraphqlMatchers
    # Matcher for testing graphql types
    class SuccessfulGraphqlControllerResponseMatcher # rubocop:disable Metrics/ClassLength
      DEFAULT_ERROR_MESSAGE = 'expected request to be successful'

      def matches?(controller_response)
        @controller_response = controller_response

        validate_response_status && validate_response_type
      end

      def failure_message
        error_message || DEFAULT_ERROR_MESSAGE
      end

      private

      attr_reader :controller_response, :error_message

      def validate_response_status
        return true if controller_response.success?

        messages = controller_response.errors.map { _1.try(:message) }.compact
        message = "#{DEFAULT_ERROR_MESSAGE}, but got errors:\n" \
                  "#{messages.take(5).join("\n").indent(2)}"
        add_error(message)
        false
      end

      def validate_response_type
        validate_response_type_null_matching &&
          validate_response_type_list_matching &&
          validate_graphql_model_matching &&
          validate_response_graphql_attributes_matching

        error_message.nil?
      end

      def validate_response_type_null_matching
        if action_response_graphql_type.non_null? && response_result.nil?
          add_error('Response type is not nullable, but the result is nil')
        end

        error_message.nil?
      end

      def validate_response_type_list_matching
        if action_response_graphql_type.list? && !list_response?
          add_error('Response type is a list, but the result is not a list-like object')
        elsif !action_response_graphql_type.list? && list_response?
          add_error('Response type is not a list, but the result is a list-like object')
        end

        error_message.nil?
      end

      def validate_graphql_model_matching
        return true if action_response_graphql_model.nil?

        mismatching_item = result_items.compact.find { !_1.is_a?(action_response_graphql_model) }
        return true if mismatching_item.nil?

        add_error(
          "Expected response to be an instance of #{action_response_graphql_model}, " \
          "but it's #{mismatching_item.class}"
        )
        false
      end

      def validate_response_graphql_attributes_matching
        messages = result_items.each_with_index.flat_map do |item, index|
          prefix = list_response? ? "[#{index}] " : ''
          item_error_messages(item).map { "#{prefix}#{_1}" }
        end
        return if messages.empty?

        add_error("Response type does not match the expected type:\n#{messages.take(5).join("\n").indent(2)}")
      end

      def item_error_messages(item)
        return item_nullability_error_messages if item.nil?

        matcher = TypeMatcher.new(action_response_graphql_type.unwrap, deeply: false, strictly: false)
        matcher.matches?(item)
        matcher.error_messages
      end

      def item_nullability_error_messages
        list_type = action_response_graphql_type
        list_type = list_type.of_type if list_type.non_null?
        list_type.of_type.non_null? ? ['expected non-nullable list item not to be `nil`'] : []
      end

      def result_items
        @result_items ||=
          if response_result.nil?
            []
          elsif list_response?
            response_result.map(&:itself)
          else
            [response_result]
          end
      end

      def list_response?
        return false if response_result.is_a?(Hash)
        return false if defined?(ActionController::Parameters) && response_result.is_a?(ActionController::Parameters)

        response_result.respond_to?(:each)
      end

      def controller
        controller_response.controller
      end

      def action_name
        controller_response.action_name
      end

      def response_result
        controller_response.result
      end

      def action_response_graphql_type
        @action_response_graphql_type ||= controller.action(action_name).type_parser.graphql_type
      end

      def action_response_graphql_model
        return @action_response_graphql_model if defined?(@action_response_graphql_model)

        @action_response_graphql_model = controller.action(action_name).type_parser.graphql_model
      end

      def add_error(error_message)
        @error_message = error_message
      end
    end
  end
end
