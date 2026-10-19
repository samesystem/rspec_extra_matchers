# frozen_string_literal: true

require_relative 'graphql_model_instance'
require_relative 'union_type_resolver'

module RSpecExtraMatchers
  module GraphqlMatchers
    # Matcher for testing graphql types
    class AssertTypeAndValue # rubocop:disable Metrics/ClassLength
      ValueExecutionError = Class.new(StandardError)
      MissingFieldError = Class.new(StandardError)

      def initialize(type:, value_parent:, deeply:, strictly:, field_name: nil, checked_records: Set.new, property: nil, # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength
                     field: nil, owner_type: nil, graphql_context: nil)
        @value_parent = value_parent
        @deeply = deeply
        @strictly = strictly
        @type = type
        @field_name = field_name
        @checked_records = checked_records
        @detailed_error_messages = []
        @property = property
        @field = field
        @owner_type = owner_type
        @graphql_context = graphql_context
      end

      def call
        assert_type_and_value

        detailed_error_messages
      end

      private

      attr_reader :detailed_error_messages, :type, :checked_records, :value_parent, :field_name, :property, :field,
                  :owner_type, :graphql_context

      def assert_type_and_value # rubocop:disable Metrics/AbcSize
        return add_missing_method_error unless parent_method_exist?

        return assert_nullable if value.nil?
        return assert_list if list_value?
        return assert_basic_type if basic_type?
        return assert_enum_type if enum_type?

        assert_complex_type
      rescue MissingFieldError
        add_missing_method_error
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
        return if GraphqlModelInstance.call(value, graphql_model)

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
        assert_basic_type_for(value:, type:)
      end

      def assert_basic_type_for(value:, type:)
        compatible_classes = fetch_compatible_classes(type:)
        return assert_coerced_scalar(value:, type:) if compatible_classes.nil?
        return if compatible_classes.any? { |klass| value.is_a?(klass) }

        expected_type =
          if compatible_classes.count > 1
            "one of `#{compatible_classes}`"
          else
            "`#{compatible_classes.first}`"
          end

        add_error(:wrong_type, expected_type:, actual_type: value.class.to_s)
      end

      def assert_coerced_scalar(value:, type:)
        type.unwrap.coerce_result(value, GraphQL::Query::NullContext.instance)
      rescue StandardError => e
        add_error(:wrong_scalar_value, value: value.inspect, error: e.message)
      end

      # Scalars without a class list, such as custom and date scalars, are checked through `coerce_result`.
      # The other built-in scalars keep one, since their `coerce_result` accepts almost any value.
      # `ISO8601Date` is lenient too: it accepts anything whose `to_s` parses as a date, such as `20240101`.
      def fetch_compatible_classes(type:) # rubocop:disable Metrics/MethodLength
        inner_type = type.unwrap
        if inner_type <= GraphQL::Types::Int
          [Integer]
        elsif inner_type <= GraphQL::Types::ID
          [Integer, String, Symbol]
        elsif inner_type <= GraphQL::Types::String
          [String, Symbol, Numeric, Date, Time]
        elsif inner_type <= GraphQL::Types::Float
          [Float, Integer, Numeric]
        elsif inner_type <= GraphQL::Types::Boolean
          [TrueClass, FalseClass]
        elsif inner_type <= GraphQL::Types::JSON
          [Hash, Array, String, Integer, Float, TrueClass, FalseClass, NilClass]
        end
      end

      def assert_enum_type(value: self.value, type: self.type, field_name: self.field_name)
        expected_values = type.unwrap.values.values.map(&:value)
        return if expected_values.include?(value)

        message_options = {
          field_name:,
          expected_values: expected_values.inspect,
          actual_value: value.inspect
        }
        add_error(:wrong_enum_value, **message_options)
      end

      def assert_nested_fields(value, type:, prefix: '')
        unwrapped_type = type.unwrap
        item_field_name = "#{field_name}#{prefix}"
        return assert_basic_type_for(value:, type: unwrapped_type) if basic_type?(unwrapped_type)
        return assert_enum_type(value:, type: unwrapped_type, field_name: item_field_name) if enum_type?(unwrapped_type)

        object_type = resolve_object_type(unwrapped_type, value:, field_name: item_field_name)
        object_type&.fields&.each_value do |field|
          assert_nested_type(value, field:, owner_type: object_type, suffix: "#{prefix}.#{field.name}")
        end
      end

      def resolve_object_type(type, value:, field_name:)
        return type unless UnionTypeResolver.union?(type)

        resolved_type = UnionTypeResolver.call(type, value)
        return resolved_type if resolved_type

        add_error(:unresolved_union_type, union: type.graphql_name, field_name:, value: value.inspect)
        nil
      end

      def assert_nested_type(value_parent, field:, owner_type:, suffix: '') # rubocop:disable Metrics/MethodLength
        full_field_name = "#{field_name}#{suffix}"
        all_checked_records = checked_records + [value_parent]
        errors = self.class.new(
          type: field.type,
          field_name: full_field_name,
          value_parent:,
          checked_records: all_checked_records,
          deeply: @deeply,
          strictly: @strictly,
          property: field.method_str,
          field:,
          owner_type:,
          graphql_context:
        ).call

        @detailed_error_messages += errors
      end

      def basic_type?(type = self.type)
        type.unwrap < GraphQL::Schema::Scalar
      end

      def enum_type?(type = self.type)
        type.unwrap < GraphQL::Schema::Enum
      end

      def add_error(type, **message_options)
        @detailed_error_messages << { type:, field_name:, **message_options }
      end

      # GraphqlRails resolves attributes with `send`, so private methods are valid too.
      # GraphQL resolves Hash objects by key, and a missing key resolves to `nil`.
      def parent_method_exist?
        value_parent.is_a?(Hash) || value_parent.respond_to?(property, true)
      end

      # Like GraphQL, a resolver method on the type wins over a Hash key lookup.
      # Interfaces are modules and can't be instantiated, so they fall back to the key lookup.
      def type_resolver?
        value_parent.is_a?(Hash) && owner_type.is_a?(Class) &&
          owner_type.public_method_defined?(field.resolver_method)
      end

      def value
        return @value if defined?(@value)

        @value =
          if type_resolver?
            type_resolver_value
          elsif value_parent.is_a?(Hash)
            hash_value
          else
            with_graphql_context { value_parent.send(property) }
          end
      rescue MissingFieldError
        raise
      rescue Exception => e
        raise ValueExecutionError, e.message do
          set_backtrace e.backtrace
        end
      end

      # Types GraphqlRails built set the query context for the duration of each field call;
      # plain graphql-ruby types leave it unset.
      def with_graphql_context(&)
        return yield if graphql_context.nil? || !graphql_rails_field?

        value_parent.with_graphql_context(graphql_context, &)
      end

      def graphql_rails_field?
        defined?(GraphqlRails::Types::ObjectType) && owner_type.is_a?(Class) &&
          owner_type < GraphqlRails::Types::ObjectType && value_parent.respond_to?(:with_graphql_context)
      end

      # Not supported: resolver arguments (the method is called without any), a real query context (graphql-ruby
      # types get `NullContext` by design), and `hash_key:`, which GraphQL checks before the resolver method.
      def type_resolver_value
        owner_type.send(:new, value_parent, GraphQL::Query::NullContext.instance).public_send(field.resolver_method)
      rescue NoMethodError => e
        # GraphqlRails resolvers call the attribute method on the Hash itself
        raise MissingFieldError if missing_on_hash?(e)

        raise
      end

      def missing_on_hash?(error)
        error.name == property.to_sym && error.receiver.equal?(value_parent)
      rescue ArgumentError # raised by #receiver when the error was built without one
        false
      end

      # Mirrors GraphQL::Schema::Field's plain Hash lookup: a Hash default value is ignored, but a default proc
      # is called. Field options such as `hash_key:`, `dig:` and `fallback_value:` are not supported.
      def hash_value
        if value_parent.key?(property.to_sym)
          value_parent[property.to_sym]
        elsif value_parent.key?(property.to_s) || value_parent.default_proc
          value_parent[property.to_s]
        end
      end
    end
  end
end
