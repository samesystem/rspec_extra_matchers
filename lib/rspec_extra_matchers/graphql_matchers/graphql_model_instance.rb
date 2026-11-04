# frozen_string_literal: true

require 'delegate'

module RSpecExtraMatchers
  module GraphqlMatchers
    # Checks whether a value can be served as the given GraphqlRails model
    module GraphqlModelInstance
      module_function

      # An STI record may come back as its own subclass rather than the declared one. GraphQL serialises it with the
      # declared type, so any record sharing the declared model's ActiveRecord base_class is accepted.
      # Delegator does not forward `is_a?`, but GraphQL resolves fields on the delegator as on the object it wraps,
      # so each layer of a Delegator chain is checked, the delegator itself first.
      def call(value, model)
        delegator_layers(value).any? { _1.is_a?(model) || same_base_class?(_1.class, model) }
      end

      # The outermost layer that is a GraphqlRails model: a decorator built on Delegator may be one itself
      def graphql_rails_record(value)
        return unless defined?(GraphqlRails::Model)

        delegator_layers(value).find { _1.is_a?(GraphqlRails::Model) }
      end

      def unwrap_delegator(value)
        delegator_layers(value).last
      end

      def delegator_layers(value)
        layers = [value]
        layers << value = value.__getobj__ while value.is_a?(Delegator)
        layers
      end

      def same_base_class?(klass, model)
        klass.respond_to?(:base_class) && model.respond_to?(:base_class) && klass.base_class == model.base_class
      end
    end
  end
end
