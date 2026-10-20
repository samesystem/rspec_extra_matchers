# frozen_string_literal: true

module RSpecExtraMatchers
  module GraphqlMatchers
    # Checks whether a value can be served as the given GraphqlRails model
    module GraphqlModelInstance
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
        attributes = model.graphql.attributes.values
        attributes.any? && attributes.all? { |attribute| attribute_method?(value, attribute.property) }
      end

      # Methods every object has, such as Kernel's private `format` or ActiveSupport's `try`, don't count.
      # `method` is called unbound, since a value may define its own `method`, as a Struct member can.
      def attribute_method?(value, name)
        return false unless value.respond_to?(name, true)

        !Object.ancestors.include?(Kernel.instance_method(:method).bind_call(value, name).owner)
      rescue NameError
        true
      end
    end
  end
end
