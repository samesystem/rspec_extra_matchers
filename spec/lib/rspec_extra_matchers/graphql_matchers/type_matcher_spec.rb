# frozen_string_literal: true

require 'rspec_extra_matchers/graphql_matchers/type_matcher'
require 'graphql_rails'

# rubocop:disable RSpec/VerifiedDoubles
RSpec.describe RSpecExtraMatchers::GraphqlMatchers::TypeMatcher do
  subject(:matcher) { described_class.new(graphql_type) }

  let(:record_class) { Struct.new(:id, :name, :location, keyword_init: true) }
  let(:record) { record_class.new(record_params) }
  let(:record_params) { { id: '123', name: 'John', location: nil } }
  let(:graphql_type) do
    Class.new do
      include GraphqlRails::Model

      graphql do |c|
        c.name("DummyUser#{rand(1**10)}")
        c.attribute(:id).type('ID!')
        c.attribute(:name).type('String!')
      end
    end
  end

  describe '#error_messages' do
    subject(:error_messages) { matcher.error_messages }

    before do
      matcher.matches?(record)
    end

    context 'when record matches graphql type' do
      context 'when graphql type is a GraphqlRails::Model' do
        it { is_expected.to be_empty }
      end

      context 'when graphql type is a GraphQL::Schema::Object' do
        let(:graphql_type) do
          Class.new(GraphQL::Schema::Object) do
            graphql_name "DummyUser#{rand(1**10)}"
            field :id, GraphQL::Types::ID, null: false
            field :name, String, null: false
          end
        end

        it { is_expected.to be_empty }
      end
    end

    context 'when record field is nil, but graphql field is non-nullable' do
      let(:record_params) { super().merge(name: nil) }

      it 'returns error message' do
        expect(error_messages).to eq(['expected non-nullable field "name" not to be `nil`'])
      end
    end

    context 'when field on record does not exist' do
      let(:record) { Struct.new(:id).new(1337) }

      it 'returns error message', :aggregate_failures do
        expect(error_messages.size).to eq(1)
        expect(error_messages.first).to match(/Method `name` for "name" field does not exist on record/)
      end
    end

    context 'when field method on record is private' do
      let(:record) do
        Class.new do
          private

          def id = '1'
          def name = 'John'
        end.new
      end

      it { is_expected.to be_empty }
    end

    context 'when record field class in not compatible with graphql type field' do
      let(:record_params) { super().merge(name: true) }

      it 'returns error message' do
        expect(error_messages)
          .to eq(['Expected field "name" to be one of `[String, Symbol, Numeric, Date, Time]`, but was `TrueClass`'])
      end
    end

    context 'when string field value is a Symbol' do
      let(:record_params) { super().merge(name: :john) }

      it { is_expected.to be_empty }
    end

    context 'when string field value is a Date' do
      let(:record_params) { super().merge(name: Date.new(2024, 1, 1)) }

      it { is_expected.to be_empty }
    end

    context 'when ID field value is a Symbol' do
      let(:record_params) { super().merge(id: :sale) }

      it { is_expected.to be_empty }
    end

    context 'when record is a Hash' do
      context 'with symbol keys' do
        let(:record) { { id: '1', name: 'John' } }

        it { is_expected.to be_empty }
      end

      context 'with string keys' do
        let(:record) { { 'id' => '1', 'name' => 'John' } }

        it { is_expected.to be_empty }
      end

      context 'when non-nullable key is missing' do
        let(:record) { { id: '1' } }

        it 'returns error message' do
          expect(error_messages).to eq(['expected non-nullable field "name" not to be `nil`'])
        end
      end

      context 'when value has the wrong type' do
        let(:record) { { id: '1', name: true } }

        it 'returns error message' do
          expect(error_messages)
            .to eq(['Expected field "name" to be one of `[String, Symbol, Numeric, Date, Time]`, but was `TrueClass`'])
        end
      end
    end

    context 'when graphql type is a scalar' do
      let(:graphql_type) { GraphQL::Types::Boolean.to_non_null_type }

      context 'when value matches the scalar' do
        let(:record) { true }

        it { is_expected.to be_empty }
      end

      context 'when value does not match the scalar' do
        let(:record) { 'yes' }

        it 'returns error message' do
          expect(error_messages)
            .to eq(['Expected field "Boolean" to be one of `[TrueClass, FalseClass]`, but was `String`'])
        end
      end
    end

    context 'when graphql type is an enum' do
      let(:graphql_type) do
        Class.new(GraphQL::Schema::Enum) do
          graphql_name "DummyRole#{rand(10**9)}Enum"
          value 'ADMIN', value: :admin
        end
      end

      context 'when value matches the enum' do
        let(:record) { :admin }

        it { is_expected.to be_empty }
      end

      context 'when value does not match the enum' do
        let(:record) { :guest }

        it 'returns error message' do
          expect(error_messages.first).to match(/enum field to be one of \[:admin\], but was `:guest`/)
        end
      end
    end

    context 'when type references itself' do
      let(:graphql_type) do
        Class.new(GraphQL::Schema::Object) do
          graphql_name "DummyUser#{rand(1**10)}"
          field :id, GraphQL::Types::ID, null: false
          field :itself, self, null: false
        end
      end

      it { is_expected.to be_empty }
    end

    context 'with enum type' do
      let(:graphql_enum_type) do
        Class.new(GraphQL::Schema::Enum) do
          graphql_name "DummyUserRole#{rand(1**10)}Enum"
          value 'ADMIN', value: :admin
          value 'REGULAR', value: :regular
        end
      end

      let(:graphql_type) do
        enum = graphql_enum_type
        Class.new(super()) do
          graphql.attribute(:role).type(enum)
        end
      end

      let(:record_class) { Struct.new(:id, :name, :location, :role, keyword_init: true) }
      let(:record_params) { super().merge(role: :admin) }

      context 'when value matches enum' do
        it { is_expected.to be_empty }
      end

      context 'when value does not match enum' do
        let(:record_params) { super().merge(role: :invalid) }

        it 'returns error message' do
          expect(error_messages)
            .to eq(['Expected value of the "role" enum field to be one of [:admin, :regular], but was `:invalid`'])
        end
      end

      context 'when field is a list of enums' do
        let(:graphql_type) do
          enum = graphql_enum_type
          Class.new(GraphQL::Schema::Object) do
            graphql_name "DummyUser#{rand(10**9)}"
            field :roles, [enum], null: false
          end
        end

        let(:record) { Struct.new(:roles).new(roles) }

        context 'when all values match enum' do
          let(:roles) { %i[admin regular] }

          it { is_expected.to be_empty }
        end

        context 'when one value does not match enum' do
          let(:roles) { %i[admin invalid] }

          it 'returns error message' do
            expect(error_messages)
              .to eq(['Expected value of the "roles[1]" enum field to be one of [:admin, :regular], but was `:invalid`'])
          end
        end
      end
    end

    context 'with custom scalar type' do
      let(:hour_scalar) do
        Class.new(GraphQL::Schema::Scalar) do
          graphql_name "DummyHour#{rand(1**10)}"

          def self.coerce_result(value, _context)
            Integer(value)
          end
        end
      end

      let(:graphql_type) do
        scalar = hour_scalar
        Class.new(super()) do
          graphql.attribute(:hour).type(scalar)
        end
      end

      let(:record_class) { Struct.new(:id, :name, :location, :hour, keyword_init: true) }

      context 'when value can be coerced by the scalar' do
        let(:record_params) { super().merge(hour: 12) }

        it { is_expected.to be_empty }
      end

      context 'when value can not be coerced by the scalar' do
        let(:record_params) { super().merge(hour: 'noon') }

        it 'returns error message' do
          expect(error_messages.first).to start_with('Scalar "hour" field can not serialize value "noon":')
        end
      end
    end

    context 'with union type' do
      let(:matcher) { super().tap(&:deeply) }

      let(:post_type) do
        Class.new(GraphQL::Schema::Object) do
          graphql_name "DummyPost#{rand(10**9)}"
          field :title, String, null: false
        end
      end

      let(:poll_type) do
        Class.new(GraphQL::Schema::Object) do
          graphql_name "DummyPoll#{rand(10**9)}"
          field :question, String, null: false
        end
      end

      let(:post_class) { Struct.new(:title) }
      let(:poll_class) { Struct.new(:question) }

      let(:content_union) do
        post, poll, post_class = [post_type, poll_type, self.post_class]
        Class.new(GraphQL::Schema::Union) do
          graphql_name "DummyContent#{rand(10**9)}"
          possible_types post, poll

          define_singleton_method(:resolve_type) do |object, _context|
            object.is_a?(post_class) ? post : poll
          end
        end
      end

      let(:graphql_type) do
        union = content_union
        Class.new(super()) do
          graphql.attribute(:contents).type(union.to_non_null_type.to_list_type)
        end
      end

      let(:record_class) { Struct.new(:id, :name, :location, :contents, keyword_init: true) }
      let(:record_params) { super().merge(contents:) }

      context 'when each item matches its resolved type' do
        let(:contents) { [post_class.new('Hello'), poll_class.new('Why?')] }

        it { is_expected.to be_empty }
      end

      context 'when item does not match its resolved type' do
        let(:contents) { [post_class.new('Hello'), poll_class.new(nil)] }

        it 'returns error message' do
          expect(error_messages).to eq(['expected non-nullable field "contents[1].question" not to be `nil`'])
        end
      end

      context 'when union can not resolve the type' do
        let(:content_union) do
          post, poll = [post_type, poll_type]
          Class.new(GraphQL::Schema::Union) do
            graphql_name "DummyContent#{rand(10**9)}"
            possible_types post, poll

            def self.resolve_type(_object, _context) = nil
          end
        end

        let(:contents) { [post_class.new('Hello')] }

        it 'returns error message' do
          expect(error_messages.first).to match(/Could not resolve union type .* for "contents\[0\]" field value/)
        end
      end

      context 'when graphql type itself is a union' do
        let(:graphql_type) { content_union }
        let(:record) { poll_class.new('Why?') }

        it { is_expected.to be_empty }
      end
    end

    context 'with custom inner type' do
      let(:matcher) { super().tap(&:deeply) }

      let(:location_type) do
        Class.new(GraphQL::Schema::Object) do
          graphql_name "DummyLocation#{rand(1**10)}"
          field :country, String, null: false
          field :city, String, null: false
        end
      end

      let(:graphql_type) do
        location = location_type
        Class.new(super()) do
          graphql.attribute(:location).type(location)
        end
      end

      let(:record_class) { Struct.new(:id, :name, :location, keyword_init: true) }
      let(:record_params) { super().merge(location:) }
      let(:location) { double('Location', country: 'USA', city: 'New York') }

      context 'when using deep mode' do
        context 'when record matches graphql type' do
          it { is_expected.to be_empty }
        end

        context 'when nested type does not match' do
          let(:record_params) { super().merge(location: invalid_location) }
          let(:location) { Struct.new(:country, :city).new('USA', 123) }
          let(:invalid_location) { double('InvalidLocation', country: 'USA', city: true) }

          it 'returns error message' do
            expect(error_messages)
              .to eq(['Expected field "location.city" to be one of `[String, Symbol, Numeric, Date, Time]`, ' \
                      'but was `TrueClass`'])
          end
        end

        context 'when nested type is an array' do
          let(:record_class) { Struct.new(:id, :name, :location, :locations, keyword_init: true) }
          let(:graphql_type) do
            location = location_type
            Class.new(super()) do
              graphql.attribute(:locations).type(location.to_list_type)
            end
          end
          let(:record_params) { super().merge(locations:) }
          let(:locations) { [location, location2] }
          let(:location2) { double('Location2', country: 'USA', city: 'Washington') }

          context 'when nested type matches' do
            it { is_expected.to be_empty }
          end

          context 'when one array item does not match' do
            let(:invalid_location) { double('InvalidLocation', country: 'USA', city: true) }
            let(:locations) { [location, invalid_location] }

            it 'returns error message' do
              expect(error_messages)
                .to eq(['Expected field "locations[1].city" to be one of `[String, Symbol, Numeric, Date, Time]`, ' \
                     'but was `TrueClass`'])
            end
          end
        end
      end

      context 'when using shallow mode' do
        let(:matcher) { super().tap(&:shallow) }

        context 'when record matches graphql type' do
          it { is_expected.to be_empty }
        end

        context 'when nested type does not match' do
          let(:record_params) { super().merge(location: invalid_location) }
          let(:location) { Struct.new(:country, :city).new('USA', 123) }
          let(:invalid_location) { double('InvalidLocation', country: 'USA', city: 123) }

          it { is_expected.to be_empty }
        end
      end
    end
  end
end
# rubocop:enable RSpec/VerifiedDoubles
