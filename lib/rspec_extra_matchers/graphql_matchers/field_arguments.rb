# frozen_string_literal: true

require 'active_support/core_ext/string/inflections'

module RSpecExtraMatchers
  module GraphqlMatchers
    # Finds the arguments given for a field, keyed by its path such as `user` or `user.posts`
    module FieldArguments
      module_function

      # Path segments may be GraphQL or Ruby names (`existing_resource` or `existingResource`).
      # List indexes are ignored, so `users.posts` applies to `users[0].posts` and every other item.
      def call(arguments, field_path)
        segments = field_path.to_s.gsub(/\[\d+\]/, '').split('.')
        arguments.each do |path, field_arguments|
          return field_arguments.transform_keys(&:to_sym) if same_path?(path.to_s.split('.'), segments)
        end

        {}
      end

      def same_path?(path, segments)
        path.size == segments.size &&
          path.zip(segments).all? { |name, segment| name == segment || name.camelize(:lower) == segment }
      end
    end
  end
end
