# frozen_string_literal: true

module RSpecExtraMatchers
  module GraphqlMatchers
    # Checks whether a value can be served as the given GraphqlRails model
    module GraphqlModelInstance
      module_function

      # An STI record may come back as its own subclass rather than the declared one. GraphQL serialises it with the
      # declared type, so any record sharing the declared model's ActiveRecord base_class is accepted.
      def call(value, model)
        value.is_a?(model) || same_base_class?(value.class, model)
      end

      def same_base_class?(klass, model)
        klass.respond_to?(:base_class) && model.respond_to?(:base_class) && klass.base_class == model.base_class
      end
    end
  end
end
