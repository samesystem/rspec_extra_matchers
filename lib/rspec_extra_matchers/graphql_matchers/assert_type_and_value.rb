# frozen_string_literal: true

module RSpecExtraMatchers
  module GraphqlMatchers
    # Matcher for testing graphql types
    class AssertTypeAndValue # rubocop:disable Metrics/ClassLength
      ValueExecutionError = Class.new(StandardError)

      def initialize(type:, value_parent:, deeply:, strictly:, field_name: nil, checked_records: Set.new, property: nil) # rubocop:disable Metrics/ParameterLists
        @value_parent = value_parent
        @deeply = deeply
        @strictly = strictly
        @type = type
        @field_name = field_name
        @checked_records = checked_records
        @detailed_error_messages = []
        @property = property
      end

      def call
        assert_type_and_value

        detailed_error_messages
      end

      private

      attr_reader :detailed_error_messages, :type, :checked_records, :value_parent, :field_name, :property

      def assert_type_and_value # rubocop:disable Metrics/AbcSize
        return add_missing_method_error unless parent_method_exist?

        return assert_nullable if value.nil?
        return assert_list if list_value?
        return assert_basic_type if basic_type?
        return assert_enum_type if enum_type?

        assert_complex_type
      rescue ValueExecutionError => e
        add_error(:raises_error, property:, field_name:, error: e.message)
      end

      def assert_complex_type
        assert_graphql_rails_model if graphql_model?
        assert_nested_fields(value, type:) if assert_deeply?(value)
      end

      def graphql_model?
        return false unless defined?(GraphqlRails::Model)
        return false unless value_parent.is_a?(GraphqlRails::Model)

        attribute_model = graphql_rails_attribute.graphql_model
        attribute_model.is_a?(Class) && attribute_model < GraphqlRails::Model
      end

      def graphql_rails_attribute
        return @graphql_rails_attribute if defined?(@graphql_rails_attribute)

        @graphql_rails_attribute =
          value_parent
          .class
          .graphql
          .attributes
          .values
          .detect { |attr| attr.property == property }
      end

      def assert_graphql_rails_model
        graphql_model = graphql_rails_attribute.graphql_model
        return if value.is_a?(graphql_model)

        expected_type = graphql_model.name.presence || graphql_model.to_s
        actual_type = value.class.name
        add_error(:graphql_rails_type_mismatch, value: value.inspect, expected_type:, actual_type:)
      end

      def assert_deeply?(value)
        @deeply && !checked_records.include?(value)
      end

      def strict?
        @strictly
      end

      def list_value?
        return true if value.is_a?(Array)
        return true if defined?(ActiveRecord::Relation) && value.is_a?(ActiveRecord::Relation)

        defined?(GraphqlRails::Decorator::RelationDecorator) && value.is_a?(GraphqlRails::Decorator::RelationDecorator)
      end

      def add_missing_method_error
        add_error(:missing_field, property:, record: value_parent.inspect)
      end

      def assert_nullable
        if type.non_null?
          add_error(:not_nullable)
        elsif strict?
          add_error(:nil_in_strict_mode)
        end
      end

      def assert_list
        value.each.with_index do |item, i|
          assert_nested_fields(item, type: unwrap_list(type), prefix: "[#{i}]")
        end
      end

      def unwrap_list(type)
        type = type.of_type while type.list?
        type
      end

      def assert_basic_type
        assert_basic_type_for(value:, compatible_classes:)
      end

      def compatible_classes
        @compatible_classes ||= fetch_compatible_classes(value:, type:)
      end

      def assert_basic_type_for(value:, compatible_classes:)
        return if compatible_classes.any? { |klass| value.is_a?(klass) }

        expected_type =
          if compatible_classes.count > 1
            "one of `#{compatible_classes}`"
          else
            "`#{compatible_classes.first}`"
          end

        add_error(:wrong_type, expected_type:, actual_type: value.class.to_s)
      end

      def fetch_compatible_classes(value:, type:) # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize
        inner_type = type.unwrap
        if inner_type <= GraphQL::Types::Int
          [Integer]
        elsif inner_type <= GraphQL::Types::ID
          [Integer, String]
        elsif inner_type <= GraphQL::Types::String
          [String, Numeric]
        elsif inner_type <= GraphQL::Types::Float
          [Float, Integer, Numeric]
        elsif inner_type <= GraphQL::Types::Boolean
          [TrueClass, FalseClass]
        elsif inner_type <= GraphQL::Types::ISO8601DateTime
          [Time, DateTime]
        elsif inner_type <= GraphQL::Types::ISO8601Date
          [Date, ActiveSupport::TimeWithZone]
        elsif inner_type <= GraphQL::Types::JSON
          [Hash, Array, String, Integer, Float, TrueClass, FalseClass, NilClass]
        else
          raise "Unknown scalar type #{graphql_scalar}"
        end
      end

      def assert_enum_type
        expected_values = type.unwrap.values.values.map(&:value)
        return if expected_values.include?(value)

        message_options = {
          expected_values: expected_values.inspect,
          actual_value: value.inspect
        }
        add_error(:wrong_enum_value, **message_options)
      end

      def assert_nested_fields(value, type:, prefix: '')
        unwrapped_type = type.unwrap
        return assert_nested_basic_type(value, type: unwrapped_type) if basic_type?(unwrapped_type)

        type.unwrap.fields.each_value do |field|
          assert_nested_type(value, type: field.type, suffix: "#{prefix}.#{field.name}", property: field.method_str)
        end
      end

      def assert_nested_basic_type(value, type:)
        assert_basic_type_for(value:, compatible_classes: fetch_compatible_classes(value:, type:))
      end

      def assert_nested_type(value_parent, type:, suffix: '', property: self.property) # rubocop:disable Metrics/MethodLength
        full_field_name = "#{field_name}#{suffix}"
        all_checked_records = checked_records + [value_parent]
        errors = self.class.new(
          type:,
          field_name: full_field_name,
          value_parent:,
          checked_records: all_checked_records,
          deeply: @deeply,
          strictly: @strictly,
          property:
        ).call

        @detailed_error_messages += errors
      end

      def basic_type?(type = self.type)
        type.unwrap < GraphQL::Schema::Scalar
      end

      def enum_type?
        type.unwrap < GraphQL::Schema::Enum
      end

      def add_error(type, **message_options)
        @detailed_error_messages << { type:, field_name:, **message_options }
      end

      def parent_method_exist?
        value_parent.respond_to?(property)
      end

      def value
        return @value if defined?(@value)

        @value = value_parent.send(property)
      rescue Exception => e
        raise ValueExecutionError, e.message do
          set_backtrace e.backtrace
        end
      end
    end
  end
end
