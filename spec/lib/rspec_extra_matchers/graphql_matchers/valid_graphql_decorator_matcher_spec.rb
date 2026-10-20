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

      context 'when value has another base class and lacks an attribute method' do
        let(:other_record_class) do
          base = Class.new do
            def self.name = 'OtherRecord'
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

    context 'when graphql field value is not a GraphqlRails::Model but responds to its attributes' do
      let(:organization) { Struct.new(:id).new('123') }

      it { is_expected.to be_empty }
    end

    context 'when graphql field value responds to only some of its attributes' do
      let(:graphql_decorator_organization) do
        Class.new do
          include GraphqlRails::Model

          def self.name = @name ||= "DummyOrganization#{rand(10**9)}"

          graphql do |c|
            c.attribute(:id).type('ID!')
            c.attribute(:title).type('String!')
          end
        end
      end
      let(:organization) { Struct.new(:id).new('123') }

      it 'returns error message' do
        expect(error_messages).to contain_exactly(
          "According to graphql configuration, #{organization.inspect} should be an " \
          "instance of #{graphql_decorator_organization.name}, but it is "
        )
      end
    end

    context 'when graphql field value responds to an attribute property that differs from its name' do
      let(:graphql_decorator_organization) do
        Class.new do
          include GraphqlRails::Model

          def self.name = @name ||= "DummyOrganization#{rand(10**9)}"

          graphql do |c|
            c.attribute(:full_name, property: :name).type('String!')
          end
        end
      end
      let(:organization) { Struct.new(:name).new('Acme') }

      it { is_expected.to be_empty }
    end

    context 'when graphql field value has a private attribute method' do
      let(:organization) do
        Class.new do
          private

          def id = '123'
        end.new
      end

      it { is_expected.to be_empty }
    end

    context 'when graphql field value has a Struct member named method' do
      let(:graphql_decorator_organization) do
        Class.new do
          include GraphqlRails::Model

          def self.name = @name ||= "DummyOrganization#{rand(10**9)}"

          graphql do |c|
            c.attribute(:method).type('String!')
          end
        end
      end
      let(:organization) { Struct.new(:method).new('GET') }

      it { is_expected.to be_empty }
    end

    context 'when graphql field value answers an attribute only through a method every object has' do
      let(:graphql_decorator_organization) do
        Class.new do
          include GraphqlRails::Model

          def self.name = @name ||= "DummyOrganization#{rand(10**9)}"

          graphql do |c|
            c.attribute(:try).type('String!')
          end
        end
      end
      let(:organization) { 'not a model' }

      it 'returns error message' do
        expect(error_messages).to contain_exactly(
          "According to graphql configuration, #{organization.inspect} should be an " \
          "instance of #{graphql_decorator_organization.name}, but it is String"
        )
      end
    end

    context 'when graphql field model has no attributes' do
      let(:graphql_decorator_organization) do
        Class.new do
          include GraphqlRails::Model

          def self.name = @name ||= "DummyOrganization#{rand(10**9)}"

          graphql { |c| c.description('Nothing to resolve') }
        end
      end
      let(:organization) { 'not a model' }

      it 'returns error message' do
        expect(error_messages).to contain_exactly(
          "According to graphql configuration, #{organization.inspect} should be an " \
          "instance of #{graphql_decorator_organization.name}, but it is String"
        )
      end
    end

    context 'when graphql field value answers an attribute only through a private Kernel method' do
      let(:graphql_decorator_organization) do
        Class.new do
          include GraphqlRails::Model

          def self.name = @name ||= "DummyOrganization#{rand(10**9)}"

          graphql do |c|
            c.attribute(:format).type('String!')
          end

          def format = 'pdf'
        end
      end
      let(:organization) { Object.new }

      it 'returns error message' do
        expect(error_messages).to contain_exactly(
          "According to graphql configuration, #{organization.inspect} should be an " \
          "instance of #{graphql_decorator_organization.name}, but it is Object"
        )
      end
    end

    context 'when graphql field value answers an attribute through method_missing and respond_to?' do
      let(:organization) do
        Class.new do
          def respond_to?(name, include_private = false) = name.to_sym == :id || super
          def method_missing(name, *) = name == :id ? '123' : super # rubocop:disable Style/MissingRespondToMissing
        end.new
      end

      it { is_expected.to be_empty }
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
