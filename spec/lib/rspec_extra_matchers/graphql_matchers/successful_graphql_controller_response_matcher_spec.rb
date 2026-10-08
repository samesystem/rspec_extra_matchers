# frozen_string_literal: true

require 'rspec_extra_matchers/graphql_matchers/successful_graphql_controller_response_matcher'
require 'graphql_rails'

RSpec.describe RSpecExtraMatchers::GraphqlMatchers::SuccessfulGraphqlControllerResponseMatcher do
  subject(:matcher) { described_class.new }

  let(:controller_response) do
    double( # rubocop:disable RSpec/VerifiedDoubles
      'controller_response',
      success?: true,
      result: response_result,
      action_name:,
      controller:,
      errors: response_errors
    )
  end

  let(:dummy_type_name) { "DummyUser#{rand(10**9)}" }

  let(:response_result) { [action_response_type.new] }
  let(:response_errors) { [Exception.new('Some error')] }
  let(:action_name) { :index }
  let(:action_response_type) do
    Class.new do
      include GraphqlRails::Model

      graphql do |c|
        c.name("DummyUser#{rand(10**9)}")
        c.attribute(:id).type('ID!')
      end

      def id
        '123'
      end
    end
  end

  let(:controller) do
    type_name = dummy_type_name
    Class.new(GraphqlRails::Controller) do
      action(:index).returns("[#{type_name}]!")
    end
  end

  before do
    Object.const_set(dummy_type_name, action_response_type)
  end

  describe '#matches?' do
    subject(:matches?) { matcher.matches?(controller_response) }

    before do
      allow(controller_response).to receive(:controller).and_return(controller)
    end

    context 'when response is successful' do
      it { is_expected.to be_truthy }
    end

    context 'when response is not successful' do
      before do
        allow(controller_response).to receive(:success?).and_return(false)
      end

      it { is_expected.to be_falsey }
    end

    context 'when response type does not match the expected type' do
      before do
        allow(controller_response).to receive(:result).and_return({})
      end

      it { is_expected.to be_falsey }
    end

    context 'when list response is empty' do
      let(:response_result) { [] }

      it { is_expected.to be_truthy }
    end

    context 'when nullable response is nil' do
      let(:response_result) { nil }
      let(:controller) do
        type_name = dummy_type_name
        Class.new(GraphqlRails::Controller) do
          action(:index).returns(type_name)
        end
      end

      it { is_expected.to be_truthy }
    end

    context 'when action is paginated' do
      let(:controller) do
        type_name = dummy_type_name
        Class.new(GraphqlRails::Controller) do
          action(:index).paginated.returns("[#{type_name}!]!")
        end
      end

      it { is_expected.to be_truthy }
    end

    context 'when non-nullable list contains nil' do
      let(:response_result) { [action_response_type.new, nil] }
      let(:controller) do
        type_name = dummy_type_name
        Class.new(GraphqlRails::Controller) do
          action(:index).returns("[#{type_name}!]!")
        end
      end

      it { is_expected.to be_falsey }
    end

    context 'when nullable list contains nil' do
      let(:response_result) { [action_response_type.new, nil] }

      it { is_expected.to be_truthy }
    end

    context 'when action returns a scalar' do
      let(:controller) do
        Class.new(GraphqlRails::Controller) do
          action(:index).returns('Boolean!')
        end
      end

      context 'when result matches the scalar' do
        let(:response_result) { true }

        it { is_expected.to be_truthy }
      end

      context 'when result does not match the scalar' do
        let(:response_result) { [1, 2] }

        it { is_expected.to be_falsey }
      end
    end

    context 'when action returns a GraphQL::Schema::Object type' do
      let(:action_response_type) do
        name = dummy_type_name
        Class.new(GraphQL::Schema::Object) do
          graphql_name name
          field :id, GraphQL::Types::ID, null: false
        end
      end
      let(:controller) do
        type_name = dummy_type_name
        Class.new(GraphqlRails::Controller) do
          action(:index).returns("#{type_name}!")
        end
      end

      context 'when result has the type fields' do
        let(:response_result) { Struct.new(:id).new('1') }

        it { is_expected.to be_truthy }
      end

      context 'when result lacks the type fields' do
        let(:response_result) { Struct.new(:name).new('x') }

        it { is_expected.to be_falsey }
      end

      context 'when the type also includes GraphqlRails::Model' do
        let(:action_response_type) do
          name = dummy_type_name
          Class.new(GraphQL::Schema::Object) do
            include GraphqlRails::Model

            graphql_name name
            field :id, GraphQL::Types::ID, null: false
          end
        end
        let(:response_result) { Struct.new(:id).new('1') }

        it { is_expected.to be_truthy }
      end
    end

    context 'when result is a Hash' do
      let(:controller) do
        type_name = dummy_type_name
        Class.new(GraphqlRails::Controller) do
          action(:index).returns("#{type_name}!")
        end
      end
      let(:action_response_type) do
        name = dummy_type_name
        Class.new(GraphQL::Schema::Object) do
          graphql_name name
          field :id, GraphQL::Types::ID, null: false
        end
      end
      let(:response_result) { { id: '1' } }

      it { is_expected.to be_truthy }
    end

    context 'when a list item other than the first does not match' do
      let(:response_result) { [action_response_type.new, Struct.new(:name).new('x')] }

      it { is_expected.to be_falsey }
    end
  end

  describe '#description' do
    it 'describes the expectation' do
      expect(matcher.description).to eq('be a successful GraphQL request returning the declared type')
    end
  end

  describe '#failure_message' do
    subject(:failure_message) do
      matcher.tap { _1.matches?(controller_response) }.failure_message
    end

    context 'when response is successful' do
      it 'returns default message' do
        expect(failure_message).to eq('expected request to be successful')
      end
    end

    context 'when response is not successful' do
      before do
        allow(controller_response).to receive(:success?).and_return(false)
      end

      it 'returns default message' do
        expect(failure_message).to eq("expected request to be successful, but got errors:\n  Some error")
      end
    end

    context 'when response type does not match the expected type' do
      let(:response_result) { 'Something' }

      context 'when response type is non-nullable, but the result is nil' do
        let(:response_result) { nil }

        it 'returns clear message' do
          expect(failure_message).to eq('Response type is not nullable, but the result is nil')
        end
      end

      context 'when response type is list, but the result is not an array' do
        let(:response_result) { action_response_type.new }

        it 'returns clear message' do
          expect(failure_message).to eq('Response type is a list, but the result is not a list-like object')
        end
      end

      context 'when inner type does not match' do
        let(:response_result) { ['Some string'] }

        it 'returns clear message' do
          expect(failure_message)
            .to eq("Expected response to be an instance of #{action_response_type}, but it's String")
        end
      end

      context 'when graphql type does not match result attributes' do
        let(:action_response_type) do
          name = dummy_type_name
          Class.new(GraphQL::Schema::Object) do
            graphql_name name
            field :id, GraphQL::Types::ID, null: false
          end
        end

        let(:response_class) { Struct.new(:name) }
        let(:response_result) { [response_class.new] }

        it 'returns clear message' do
          expect(failure_message).to include('Method `id` for "id" field does not exist on record')
        end

        context 'when only a later list item does not match' do
          let(:response_result) { [Struct.new(:id).new('1'), response_class.new] }

          it 'points to the item index' do
            expect(failure_message).to include('[1] Method `id` for "id" field does not exist on record')
          end
        end
      end
    end
  end
end
