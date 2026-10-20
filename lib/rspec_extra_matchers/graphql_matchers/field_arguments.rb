# frozen_string_literal: true

require 'active_support/core_ext/string/inflections'

module RSpecExtraMatchers
  module GraphqlMatchers
    # Finds the arguments given for a field, keyed by its path such as `user` or `user.posts`
    module FieldArguments
      module_function

      # Path segments may be GraphQL or Ruby names (`existing_resource` or `existingResource`, `active?` or `isActive`).
      # List indexes are ignored, so `users.posts` applies to `users[0].posts` and every other item.
      def call(arguments, field_path)
        segments = field_path.to_s.gsub(/\[\d+\]/, '').split('.')
        arguments.reverse_each do |path, field_arguments|
          return field_arguments.transform_keys(&:to_sym) if same_path?(path.to_s.split('.'), segments)
        end

        {}
      end

      # Moves re-given keys to the end, so the latest of several paths naming one field wins
      def merge(arguments, new_arguments)
        arguments.except(*new_arguments.keys).merge(new_arguments)
      end

      def same_path?(path, segments)
        path.size == segments.size && path.zip(segments).all? { |name, segment| graphql_names(name).include?(segment) }
      end

      # GraphqlRails names fields with ActiveSupport's camelize and turns `active?` into `isActive`;
      # graphql-ruby uses its own camelize, which ignores ActiveSupport acronyms.
      def graphql_names(name)
        name = "is_#{name.delete_suffix('?')}" if name.end_with?('?')
        [name, name.camelize(:lower), GraphQL::Schema::Member::BuildType.camelize(name)]
      end
    end
  end
end
