# frozen_string_literal: true

require 'set'

module RSpecExtraMatchers
  module GraphqlMatchers
    # Objects a deep check has already descended into, so each one is checked once.
    # Decorators are usually rebuilt on every field call, so an object with an `id` is known by its GraphQL type and
    # id, the identity GraphQL clients cache it by. Other objects are compared with `eql?`.
    class CheckedRecords
      def initialize
        @keys = Set.new
      end

      # Whether the object is new, marking it as checked
      def add?(value, type)
        !@keys.add?(key_for(value, type)).nil?
      end

      private

      def key_for(value, type)
        id = record_id(value)
        id.nil? ? value : [type.unwrap.graphql_name, id]
      end

      # The `id` field is checked on its own, so an `id` that raises here, such as one reading the GraphQL context,
      # only falls back to `eql?`
      def record_id(value)
        value.id if value.respond_to?(:id)
      rescue StandardError
        nil
      end
    end
  end
end
