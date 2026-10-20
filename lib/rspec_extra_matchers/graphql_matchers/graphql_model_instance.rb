# frozen_string_literal: true

module RSpecExtraMatchers
  module GraphqlMatchers
    # Checks whether a value can be served as the given GraphqlRails model
    module GraphqlModelInstance
      GENERIC_OWNERS = [Kernel, Object, BasicObject].freeze

      module_function

      # An STI record may come back as its own subclass rather than the declared one. GraphQL serialises it with the
      # declared type, so any record sharing the declared model's ActiveRecord base_class is accepted.
      # GraphqlRails resolves attributes with `send`, so an object with every attribute method serialises too.
      def call(value, model)
        value.is_a?(model) || same_base_class?(value.class, model) || responds_to_attributes?(value, model)
      end

      def same_base_class?(klass, model)
        klass.respond_to?(:base_class) && model.respond_to?(:base_class) && klass.base_class == model.base_class
      end

      def responds_to_attributes?(value, model)
        model.graphql.attributes.each_value.all? { |attribute| attribute_method?(value, attribute.property) }
      end

      # Private Kernel methods such as `format` or `select` answer `respond_to?(name, true)` on every object
      def attribute_method?(value, name)
        return false unless value.respond_to?(name, true)

        !GENERIC_OWNERS.include?(value.method(name).owner)
      rescue NameError
        true
      end
    end
  end
end
