# frozen_string_literal: true

module RSpecExtraMatchers
  module GraphqlMatchers
    # Finds which member of a GraphQL union the given value would be serialized as
    module UnionTypeResolver
      module_function

      def union?(type)
        type.unwrap < GraphQL::Schema::Union
      end

      def call(union, value)
        resolved = resolve_with_union(union, value) || resolve_with_graphql_rails(value)
        resolved if union.possible_types.include?(resolved)
      end

      def resolve_with_union(union, value)
        return unless union.respond_to?(:resolve_type)

        resolved = union.resolve_type(value, GraphQL::Query::NullContext.instance)
        resolved.is_a?(Array) ? resolved.first : resolved
      rescue StandardError
        nil
      end

      def resolve_with_graphql_rails(value)
        value.class.graphql.graphql_type if value.class.respond_to?(:graphql)
      end
    end
  end
end
