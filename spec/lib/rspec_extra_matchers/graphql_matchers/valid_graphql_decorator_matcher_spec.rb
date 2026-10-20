# frozen_string_literal: true

require 'rspec_extra_matchers/graphql_matchers/valid_graphql_decorator_matcher'
require 'graphql_rails'

RSpec.describe RSpecExtraMatchers::GraphqlMatchers::ValidGraphqlDecoratorMatcher do
  subject(:matcher) { described_class.new }

  let(:record_params) { { id: '123', name: 'John', organization: } }
  let(:organization) { graphql_decorator_organization.new }
  let(:graphql_decorator) do
    organization_decorator = graphql_decorator_organization

    Class.new do
      include GraphqlRails::Model

      graphql do |c|
        c.name("DummyUser#{rand(10**10)}")
        c.attribute(:id).type('ID!')
        c.attribute(:name).type('String!')
        c.attribute(:organization).type(organization_decorator).required
      end

      attr_reader :id, :name, :organization

      def initialize(id:, name:, organization:)
        @id = id
        @name = name
        @organization = organization
      end
    end
  end

  let(:graphql_decorator_organization) do
    Class.new do
      include GraphqlRails::Model

      def self.name = @name ||= "DummyOrganization#{rand(10**10)}"

      graphql do |c|
        c.attribute(:id).type('ID!')
      end

      def id = '123'
    end
  end

  let(:graphql_decorator_instance) { graphql_decorator.new(**record_params) }

  describe '#error_messages' do
    subject(:error_messages) { matcher.error_messages }

    before do
      matcher.matches?(graphql_decorator_instance)
    end

    context 'when record matches graphql type' do
      it { is_expected.to be_empty }
    end

    context 'when record field is nil, but graphql field is non-nullable' do
      let(:record_params) { super().merge(name: nil) }

      it 'returns error message' do
        expect(error_messages).to eq(['expected non-nullable field "name" not to be `nil`'])
      end
    end

    context 'when graphql field has an STI GraphqlRails::Model type' do
      let(:sti_base) do
        base = Class.new { def id = '123' }
        base.define_singleton_method(:base_class) { base }
        base
      end

      let(:graphql_decorator_organization) do
        Class.new(sti_base) do
          include GraphqlRails::Model

          def self.name = @name ||= "DummyOrganization#{rand(10**10)}"

          graphql do |c|
            c.attribute(:id).type('ID!')
          end
        end
      end

      context 'when value is its STI sibling' do
        let(:organization) { Class.new(sti_base).new }

        it { is_expected.to be_empty }
      end

      context 'when value has another base class' do
        let(:other_record_class) do
          base = Class.new do
            def self.name = 'OtherRecord'
            def id = '123'
          end
          base.define_singleton_method(:base_class) { base }
          base
        end
        let(:organization) { other_record_class.new }

        it 'returns error message' do
          expect(error_messages).to contain_exactly(
            "According to graphql configuration, #{organization.inspect} should be an " \
            "instance of #{graphql_decorator_organization.name}, but it is OtherRecord"
          )
        end
      end
    end

    context 'when graphql field takes arguments' do
      let(:graphql_decorator) do
        Class.new(super()) do
          graphql.attribute(:greeting_for).type('String!').permit(name: 'String!')

          def greeting_for(name:) = "Hi #{name}"
        end
      end

      context 'without arguments' do
        it 'returns error message' do
          expect(error_messages)
            .to eq(['Field "greetingFor" requires arguments name, pass them with `with_arguments`'])
        end
      end

      context 'with arguments' do
        let(:matcher) { described_class.new.with_arguments(greeting_for: { name: 'John' }) }

        it { is_expected.to be_empty }
      end

      context 'with arguments given in several calls' do
        let(:matcher) do
          described_class.new
            .with_arguments(greeting_for: { name: 'John' })
            .deeply
            .with_arguments(other_field: { id: 1 })
        end

        it { is_expected.to be_empty }
      end
    end

    context 'when graphql field has GraphqlRails::Model type, but value is not a GraphqlRails::Model' do
      let(:record_params) { super().merge(organization: 'not_a_model') }

      it 'returns error message' do
        expect(error_messages).to contain_exactly(
          'According to graphql configuration, "not_a_model" should be an ' \
          "instance of #{graphql_decorator_organization.name}, but it is String"
        )
      end
    end
  end
end
