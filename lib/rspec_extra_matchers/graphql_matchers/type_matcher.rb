# frozen_string_literal: true

# Usage:
# expect(user).to satisfy_graphql_type(UserDecorator)
# expect(user).to satisfy_graphql_type(Types::UserType)

require 'rspec/matchers/composable'
require_relative 'assert_type_and_value'
require_relative 'checked_records'
require_relative 'field_arguments'
require_relative 'union_type_resolver'

module RSpecExtraMatchers
  module GraphqlMatchers
    # Matcher for testing graphql types
    class TypeMatcher
      require 'rspec/matchers/composable'

      include RSpec::Matchers::Composable

      ERROR_MESSAGES = {
        not_nullable: 'expected non-nullable field "%<field_name>s" not to be `nil`',
        raises_error: 'Method `%<property>s` for "%<field_name>s" field raised an error: %<error>s',
        nil_in_strict_mode:
          'Using `strictly` matcher which does not allow `nil` values, but field "%<field_name>s" is `nil`.' \
          'Use `loosely` matcher to allow `nil` values"',
        wrong_type: 'Expected field "%<field_name>s" to be %<expected_type>s, but was `%<actual_type>s`',
        missing_field: 'Method `%<property>s` for "%<field_name>s" field does not exist on record %<record>s',
        wrong_enum_value: 'Expected value of the "%<field_name>s" enum field to be one of %<expected_values>s, ' \
                          'but was `%<actual_value>s`',
        not_a_graphql_type: 'Expected a GraphQL type, but got %<graphql_type>s',
        graphql_rails_type_mismatch: 'According to graphql configuration, %<value>s should be an instance of %<expected_type>s, but it is %<actual_type>s',
        wrong_scalar_value: 'Scalar "%<field_name>s" field can not serialize value %<value>s: %<error>s',
        unresolved_union_type: 'Could not resolve union type %<union>s for "%<field_name>s" field value %<value>s',
        missing_arguments: 'Field "%<field_name>s" requires arguments %<arguments>s, pass them with `with_arguments`'
      }.freeze

      attr_reader :detailed_error_messages, :graphql_type, :record

      def initialize(graphql_type_or_model, deeply: true, strictly: true, graphql_context: nil, field_arguments: {})
        @detailed_error_messages = []
        @graphql_context = graphql_context
        @field_arguments = field_arguments
        @deeply = deeply
        @strictly = strictly
        @graphql_type = extract_graphql_type(graphql_type_or_model)
      end

      def matches?(record)
        @record = record
        @checked_records = CheckedRecords.new
        assert_type

        error_messages.empty?
      end

      def shallow
        @deeply = false
      end

      def deeply
        @deeply = true
      end

      def strictly
        @strictly = true
      end

      def loosely
        @strictly = false
      end

      # Arguments to call fields with, keyed by field path:
      # `with_arguments(user: { id: 1 }, 'user.posts': { status: 'draft' })`
      def with_arguments(arguments)
        @field_arguments = FieldArguments.merge(field_arguments, arguments)
        self
      end

      # Query context set on GraphqlRails models while their fields are called, as GraphqlRails does at runtime:
      # `with_graphql_context(current_user: user)`
      def with_graphql_context(graphql_context)
        @graphql_context = graphql_context
        self
      end

      def failure_message
        message = "Expected #{@record} to match #{graphql_type}, but it didn't:\n"
        message + error_messages.take(5).join("\n").indent(2)
      end

      def description
        "matches GraphQL type #{graphql_type}"
      end

      def error_messages
        detailed_error_messages.map { |error| error_message_for(**error) }
      end

      private

      attr_reader :graphql_context, :field_arguments, :checked_records

      def extract_graphql_type(klass)
        graphql_rails_class?(klass) ? klass.graphql.graphql_type : klass
      end

      def graphql_rails_class?(klass)
        klass.is_a?(Class) &&
          defined?(GraphqlRails::Model) &&
          klass < GraphqlRails::Model
      end

      def strict?
        @strictly
      end

      def assert_type
        if !graphql_type.is_a?(GraphQL::Schema::Wrapper) && !(graphql_type < GraphQL::Schema::Member)
          @detailed_error_messages << { type: :not_a_graphql_type, graphql_type: }
        elsif leaf_type?
          assert_leaf_value
        else
          owner_type = object_type
          checked_records.add?(record, owner_type) if owner_type
          owner_type&.fields&.each_value { |field| assert_field(field, owner_type:) }
        end
      end

      def leaf_type?
        inner_type = graphql_type.unwrap
        inner_type < GraphQL::Schema::Scalar || inner_type < GraphQL::Schema::Enum
      end

      def assert_leaf_value
        @detailed_error_messages += AssertTypeAndValue.new(
          type: graphql_type,
          value_parent: { value: record },
          field_name: graphql_type.unwrap.graphql_name,
          deeply: deeply?,
          property: 'value',
          strictly: strict?,
          graphql_context:
        ).call
      end

      def object_type
        type = graphql_type.unwrap
        return type unless UnionTypeResolver.union?(type)

        resolved_type = UnionTypeResolver.call(type, record)
        return resolved_type if resolved_type

        @detailed_error_messages << {
          type: :unresolved_union_type, union: type.graphql_name, field_name: type.graphql_name, value: record.inspect
        }
        nil
      end

      def assert_field(field, owner_type:) # rubocop:disable Metrics/MethodLength
        @detailed_error_messages += AssertTypeAndValue.new(
          type: field.type,
          value_parent: record,
          field_name: field.name,
          deeply: deeply?,
          property: field.method_str,
          strictly: strict?,
          field:,
          owner_type:,
          graphql_context:,
          field_arguments:,
          checked_records:
        ).call
      end

      def deeply?
        @deeply
      end

      def error_message_for(type:, **error_options)
        format(ERROR_MESSAGES.fetch(type), error_options)
      end
    end
  end
end
