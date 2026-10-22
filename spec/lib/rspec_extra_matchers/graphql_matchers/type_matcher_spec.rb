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
      context 'when graphql type is a GraphQL::Schema::Object' do
        let(:graphql_type) do
          Class.new(GraphQL::Schema::Object) do
            graphql_name "DummyUser#{rand(10**9)}"
            field :id, GraphQL::Types::ID, null: false
            field :name, String, null: false
          end
        end

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

        context 'when non-nullable Boolean value is false' do
          let(:graphql_type) do
            Class.new(GraphQL::Schema::Object) do
              graphql_name "DummyUser#{rand(10**9)}"
              field :active, GraphQL::Types::Boolean, null: false
            end
          end
          let(:record) { { active: false } }

          it { is_expected.to be_empty }
        end

        context 'when non-nullable key is missing from a Hash with a default value' do
          let(:record) { Hash.new('John').merge(id: '1') }

          it 'returns error message' do
            expect(error_messages).to eq(['expected non-nullable field "name" not to be `nil`'])
          end
        end

        context 'when non-nullable key is missing from a Hash with a default proc' do
          let(:record) { Hash.new { |_hash, key| key == 'name' ? 'John' : nil }.merge(id: '1') }

          it { is_expected.to be_empty }
        end

        context 'when value has the wrong type' do
          let(:record) { { id: '1', name: true } }

          it 'returns error message' do
            expect(error_messages)
              .to eq(['Expected field "name" to be one of `[String, Symbol, Numeric, Date, Time]`, but was `TrueClass`'])
          end
        end
      end

      context 'when a field has a resolver method on the type' do
        let(:graphql_type) do
          Class.new(GraphQL::Schema::Object) do
            graphql_name "DummyResponse#{rand(10**9)}"
            field :errors, [String], null: false
            field :error, String, null: false

            def error
              object[:errors].first
            end
          end
        end

        context 'when the resolver method returns a valid value' do
          let(:record) { { errors: ['Not allowed'] } }

          it 'resolves the field with the type method, not by key' do
            expect(error_messages).to be_empty
          end
        end

        context 'when the resolver method returns an invalid value' do
          let(:record) { { errors: [], error: 'Ignored key' } }

          it 'returns error message' do
            expect(error_messages).to eq(['expected non-nullable field "error" not to be `nil`'])
          end
        end

        context 'when the resolver method calls the field name on another object' do
          let(:graphql_type) do
            Class.new(GraphQL::Schema::Object) do
              graphql_name "DummyResponse#{rand(10**9)}"
              field :error, String, null: true

              def error
                object[:errors].error
              end
            end
          end
          let(:record) { { errors: ['Not allowed'] } }

          it 'returns the raised error, not a missing field' do
            expect(error_messages.size).to eq(1)
            expect(error_messages.first).to start_with('Method `error` for "error" field raised an error: ')
            expect(error_messages.first).to include('Array')
          end
        end

        context 'when the resolver method raises a NoMethodError without a receiver' do
          let(:graphql_type) do
            Class.new(GraphQL::Schema::Object) do
              graphql_name "DummyResponse#{rand(10**9)}"
              field :error, String, null: true

              def error
                raise NoMethodError.new('error delegated to user, but user is nil', :error)
              end
            end
          end
          let(:record) { { errors: ['Not allowed'] } }

          it 'returns the raised error' do
            expect(error_messages)
              .to eq(['Method `error` for "error" field raised an error: error delegated to user, but user is nil'])
          end
        end

        context 'when the resolver method calls another missing method on the Hash' do
          let(:graphql_type) do
            Class.new(GraphQL::Schema::Object) do
              graphql_name "DummyResponse#{rand(10**9)}"
              field :error, String, null: true

              def error
                object.errors
              end
            end
          end
          let(:record) { { errors: ['Not allowed'] } }

          it 'returns the raised error, not a missing field' do
            expect(error_messages.size).to eq(1)
            expect(error_messages.first).to start_with('Method `error` for "error" field raised an error: ')
            expect(error_messages.first).to include('errors')
          end
        end

        context 'when the type method is private' do
          let(:graphql_type) do
            Class.new(GraphQL::Schema::Object) do
              graphql_name "DummyResponse#{rand(10**9)}"
              field :error, String, null: false

              private

              def error
                nil
              end
            end
          end
          let(:record) { { error: 'Not allowed' } }

          it 'reads the field by key' do
            expect(error_messages).to be_empty
          end
        end
      end

      context 'when a nested field is an interface with a resolver method' do
        let(:graphql_type) do
          interface = Module.new do
            include GraphQL::Schema::Interface

            graphql_name "DummyNamed#{rand(10**9)}"
            field :label, String, null: false

            def label
              object[:name].upcase
            end
          end

          Class.new(GraphQL::Schema::Object) do
            graphql_name "DummyOwner#{rand(10**9)}"
            field :thing, interface, null: false
          end
        end
        let(:record) { { thing: { label: 'Chair' } } }

        it 'reads the interface field by key' do
          expect(error_messages).to be_empty
        end
      end

      context 'when a field has a resolver_method inherited from a base type' do
        let(:graphql_type) do
          base_type = Class.new(GraphQL::Schema::Object) do
            def resolve_full_name
              object[:first_name]
            end
          end

          Class.new(base_type) do
            graphql_name "DummyUser#{rand(10**9)}"
            field :full_name, String, null: false, resolver_method: :resolve_full_name
          end
        end

        context 'when the resolver method returns a valid value' do
          let(:record) { { first_name: 'John' } }

          it { is_expected.to be_empty }
        end

        context 'when the resolver method returns nil and the field key is present' do
          let(:record) { { first_name: nil, full_name: 'Ignored key' } }

          it 'returns error message' do
            expect(error_messages).to eq(['expected non-nullable field "fullName" not to be `nil`'])
          end
        end
      end

      context 'when graphql type is a GraphqlRails::Model' do
        let(:record) { { id: '1', name: 'John' } }

        it 'returns error message, as GraphqlRails calls the attribute method on the Hash' do
          expect(error_messages.first).to start_with('Method `id` for "id" field does not exist on record')
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

      context 'when non-nullable scalar value is nil' do
        let(:matcher) { described_class.new(graphql_type, strictly: false) }

        let(:record) { nil }

        it 'returns error message' do
          expect(error_messages).to eq(['expected non-nullable field "Boolean" not to be `nil`'])
        end
      end

      context 'when graphql type is a list of scalars' do
        let(:matcher) { described_class.new(graphql_type, strictly: false) }

        let(:graphql_type) { GraphQL::Types::String.to_non_null_type.to_list_type }

        context 'when items match the scalar' do
          let(:record) { ['a', :b] }

          it { is_expected.to be_empty }
        end

        context 'when an item does not match the scalar' do
          let(:record) { ['a', true] }

          it 'returns error message' do
            expect(error_messages.first).to end_with('but was `TrueClass`')
          end
        end
      end

      context 'when nullable scalar value is nil in strict mode' do
        let(:graphql_type) { GraphQL::Types::String }
        let(:record) { nil }

        it 'returns error message' do
          expect(error_messages.first).to start_with('Using `strictly` matcher which does not allow `nil` values')
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

    context 'with date time type' do
      let(:graphql_type) do
        Class.new(super()) do
          graphql.attribute(:changed_at).type('DateTime!')
        end
      end

      let(:record_class) { Struct.new(:id, :name, :location, :changed_at, keyword_init: true) }

      context 'when value is a Time' do
        let(:record_params) { super().merge(changed_at: Time.new(2024, 1, 1, 12)) }

        it { is_expected.to be_empty }
      end

      context 'when value is a Date' do
        let(:record_params) { super().merge(changed_at: Date.new(2024, 1, 1)) }

        it { is_expected.to be_empty }
      end

      context 'when value is a DateTime' do
        let(:record_params) { super().merge(changed_at: DateTime.new(2024, 1, 1, 12)) }

        it { is_expected.to be_empty }
      end

      context 'when value is a well-formatted String' do
        let(:record_params) { super().merge(changed_at: '2024-01-01T12:00:00+02:00') }

        it { is_expected.to be_empty }
      end

      context 'when value is a malformed String' do
        let(:record_params) { super().merge(changed_at: 'yesterday') }

        it 'returns error message' do
          expect(error_messages.first).to start_with('Scalar "changedAt" field can not serialize value "yesterday":')
        end
      end

      context 'when value can not be serialized' do
        let(:record_params) { super().merge(changed_at: 1_704_103_200) }

        it 'returns error message' do
          expect(error_messages.first).to start_with('Scalar "changedAt" field can not serialize value 1704103200:')
        end
      end
    end

    context 'with date type' do
      let(:graphql_type) do
        Class.new(super()) do
          graphql.attribute(:born_on).type('Date!')
        end
      end

      let(:record_class) { Struct.new(:id, :name, :location, :born_on, keyword_init: true) }

      context 'when value is a Date' do
        let(:record_params) { super().merge(born_on: Date.new(2024, 1, 1)) }

        it { is_expected.to be_empty }
      end

      context 'when value is a Time' do
        let(:record_params) { super().merge(born_on: Time.new(2024, 1, 1, 12)) }

        it { is_expected.to be_empty }
      end

      context 'when value is an Integer that parses as a date, which GraphQL serializes too' do
        let(:record_params) { super().merge(born_on: 20_240_101) }

        it { is_expected.to be_empty }
      end

      context 'when value can not be serialized' do
        let(:record_params) { super().merge(born_on: 'someday') }

        it 'returns error message' do
          expect(error_messages.first).to start_with('Scalar "bornOn" field can not serialize value "someday":')
        end
      end
    end

    context 'when a GraphqlRails model field reads graphql_context' do
      let(:record) { model_class.new }
      let(:model_class) do
        Class.new do
          include GraphqlRails::Model

          graphql do |c|
            c.name("DummyContextUser#{rand(10**9)}")
            c.attribute(:name).type('String!')
          end

          def name
            graphql_context.fetch(:name)
          end
        end
      end

      let(:graphql_type) { record.class }

      context 'with a graphql_context' do
        let(:matcher) { described_class.new(graphql_type, graphql_context: { name: 'John' }) }

        it { is_expected.to be_empty }

        it 'unsets the context afterwards, as GraphqlRails does' do
          expect(record.graphql_context).to be_nil
        end
      end

      context 'without a graphql_context' do
        it 'returns error message' do
          expect(error_messages.first).to start_with('Method `name` for "name" field raised an error')
        end
      end

      context 'when a nested list item reads graphql_context' do
        let(:matcher) { described_class.new(graphql_type, graphql_context: { name: 'John' }) }
        let(:record) { parent_class.new(model_class.new) }
        let(:graphql_type) { parent_class }
        let(:parent_class) do
          child_list_type = model_class.graphql.graphql_type.to_non_null_type.to_list_type.to_non_null_type
          Class.new do
            include GraphqlRails::Model

            graphql do |c|
              c.name("DummyContextParent#{rand(10**9)}")
              c.attribute(:children).type(child_list_type)
            end

            def initialize(child)
              @child = child
            end

            def children = [@child]
          end
        end

        it { is_expected.to be_empty }
      end

      context 'when the model is reached through an interface field' do
        let(:matcher) { described_class.new(graphql_type, graphql_context: { name: 'John' }) }
        let(:record) { owner_class.new(model_class.new) }
        let(:graphql_type) { owner_class }
        let(:interface) do
          Module.new do
            include GraphQL::Schema::Interface

            graphql_name "DummyNamed#{rand(10**9)}"
            field :name, String, null: false
          end
        end
        let(:model_class) do
          named_interface = interface
          Class.new do
            include GraphqlRails::Model

            graphql do |c|
              c.name("DummyContextPet#{rand(10**9)}")
              c.implements(named_interface)
              c.attribute(:name).type('String!')
            end

            def name
              graphql_context.fetch(:name)
            end
          end
        end
        let(:owner_class) do
          named_interface = interface
          Class.new do
            include GraphqlRails::Model

            graphql do |c|
              c.name("DummyContextOwner#{rand(10**9)}")
              c.attribute(:pet).type(named_interface.to_non_null_type)
            end

            def initialize(pet)
              @pet = pet
            end

            attr_reader :pet
          end
        end

        it { is_expected.to be_empty }
      end

      context 'when the record is not a GraphqlRails model but its type is' do
        let(:matcher) { described_class.new(graphql_type, graphql_context: { name: 'John' }) }
        let(:record) { Struct.new(:name).new('John') }
        let(:graphql_type) { model_class }

        it { is_expected.to be_empty }
      end

      context 'when the record is a subclass of the declared model' do
        let(:matcher) { described_class.new(graphql_type, graphql_context: { name: 'John' }) }
        let(:record) { Class.new(model_class).new }
        let(:graphql_type) { model_class }

        it { is_expected.to be_empty }
      end

      context 'when the record is not a GraphqlRails model' do
        let(:matcher) { described_class.new(graphql_type, graphql_context: { name: 'John' }) }
        let(:graphql_type) do
          Class.new(GraphQL::Schema::Object) do
            graphql_name "DummyPlainUser#{rand(10**9)}"
            field :name, String, null: false
          end
        end
        let(:record) { Struct.new(:name).new('John') }

        it { is_expected.to be_empty }
      end

      context 'when the model sits behind a plain GraphQL type' do
        let(:matcher) { described_class.new(graphql_type, graphql_context: { name: 'John' }) }
        let(:graphql_type) do
          Class.new(GraphQL::Schema::Object) do
            graphql_name "DummyPlainUser#{rand(10**9)}"
            field :name, String, null: false
          end
        end

        it 'returns error message, since graphql-ruby leaves graphql_context unset' do
          expect(error_messages.first).to start_with('Method `name` for "name" field raised an error')
        end
      end
    end

    context 'when a field takes arguments' do
      let(:record) { model_class.new }
      let(:graphql_type) { model_class }
      let(:greeting_argument_type) { 'String!' }
      let(:model_class) do
        argument_type = greeting_argument_type
        Class.new do
          include GraphqlRails::Model

          graphql do |c|
            c.name("DummyGreeter#{rand(10**9)}")
            c.attribute(:greeting_for).type('String!').permit(name: argument_type)
          end

          def greeting_for(name: 'stranger') = "Hi #{name}"
        end
      end

      context 'without arguments' do
        it 'returns error message' do
          expect(error_messages)
            .to eq(['Field "greetingFor" requires arguments name, pass them with `with_arguments`'])
        end
      end

      context 'when the argument is optional' do
        let(:greeting_argument_type) { 'String' }

        it { is_expected.to be_empty }
      end

      context 'with arguments keyed by the Ruby name' do
        let(:matcher) { described_class.new(graphql_type).with_arguments(greeting_for: { name: 'John' }) }

        it { is_expected.to be_empty }
      end

      context 'with arguments keyed by the GraphQL name' do
        let(:matcher) { described_class.new(graphql_type).with_arguments('greetingFor' => { 'name' => 'John' }) }

        it { is_expected.to be_empty }
      end

      context 'when several required arguments are missing' do
        let(:model_class) do
          Class.new do
            include GraphqlRails::Model

            graphql do |c|
              c.name("DummyGreeter#{rand(10**9)}")
              c.attribute(:greeting_for).type('String!').permit(name: 'String!', title: 'String!')
            end

            def greeting_for(name:, title:) = "Hi #{title} #{name}"
          end
        end

        it 'returns error message' do
          expect(error_messages)
            .to eq(['Field "greetingFor" requires arguments name, title, pass them with `with_arguments`'])
        end
      end

      context 'when the argument name differs in Ruby and GraphQL' do
        let(:model_class) do
          Class.new do
            include GraphqlRails::Model

            graphql do |c|
              c.name("DummyGreeter#{rand(10**9)}")
              c.attribute(:greeting_for).type('String!').permit(user_id: 'ID!')
            end

            def greeting_for(user_id:) = "Hi #{user_id}"
          end
        end

        context 'with the Ruby keyword' do
          let(:matcher) { described_class.new(graphql_type).with_arguments(greeting_for: { user_id: 1 }) }

          it { is_expected.to be_empty }
        end

        context 'with the GraphQL name' do
          let(:matcher) { described_class.new(graphql_type).with_arguments(greeting_for: { 'userId' => 1 }) }

          it 'returns error message' do
            expect(error_messages)
              .to eq(['Field "greetingFor" requires arguments user_id, pass them with `with_arguments`'])
          end
        end
      end

      context 'when the field is a predicate' do
        let(:matcher) { described_class.new(graphql_type).with_arguments('greets?': { name: 'John' }) }
        let(:model_class) do
          Class.new do
            include GraphqlRails::Model

            graphql do |c|
              c.name("DummyGreeter#{rand(10**9)}")
              c.attribute(:greets?).type('Boolean!').permit(name: 'String!')
            end

            def greets?(name:) = !name.empty?
          end
        end

        it { is_expected.to be_empty }
      end

      context 'when the field returns the wrong type for the given arguments' do
        let(:matcher) { described_class.new(graphql_type).with_arguments(greeting_for: { name: 'John' }) }
        let(:model_class) do
          Class.new do
            include GraphqlRails::Model

            graphql do |c|
              c.name("DummyGreeter#{rand(10**9)}")
              c.attribute(:greeting_for).type('Int!').permit(name: 'String!')
            end

            def greeting_for(name:) = name
          end
        end

        it 'returns error message' do
          expect(error_messages).to eq(['Expected field "greetingFor" to be `Integer`, but was `String`'])
        end
      end

      context 'when the field is nested in a list' do
        let(:record) { parent_class.new }
        let(:graphql_type) { parent_class }
        let(:parent_class) do
          child_list_type = model_class.graphql.graphql_type.to_non_null_type.to_list_type.to_non_null_type
          child_class = model_class
          Class.new do
            include GraphqlRails::Model

            graphql do |c|
              c.name("DummyGreeterParent#{rand(10**9)}")
              c.attribute(:greeters).type(child_list_type)
            end

            define_method(:greeters) { [child_class.new, child_class.new] }
          end
        end

        context 'with arguments for its path' do
          let(:matcher) { described_class.new(graphql_type).with_arguments('greeters.greeting_for': { name: 'John' }) }

          it { is_expected.to be_empty }
        end

        context 'with arguments for another path' do
          let(:matcher) { described_class.new(graphql_type).with_arguments(greeting_for: { name: 'John' }) }

          it 'returns error message for every item' do
            expect(error_messages).to eq(
              [
                'Field "greeters[0].greetingFor" requires arguments name, pass them with `with_arguments`',
                'Field "greeters[1].greetingFor" requires arguments name, pass them with `with_arguments`'
              ]
            )
          end
        end
      end

      context 'when a graphql-ruby type resolves the field for a Hash' do
        let(:record) { {} }
        let(:graphql_type) do
          Class.new(GraphQL::Schema::Object) do
            graphql_name "DummyHashGreeter#{rand(10**9)}"

            field :greeting_for, String, null: false do
              argument :name, String
            end

            def greeting_for(name:) = "Hi #{name}"
          end
        end

        context 'with arguments' do
          let(:matcher) { described_class.new(graphql_type).with_arguments(greeting_for: { name: 'John' }) }

          it { is_expected.to be_empty }
        end

        context 'without arguments' do
          it 'returns error message' do
            expect(error_messages)
              .to eq(['Field "greetingFor" requires arguments name, pass them with `with_arguments`'])
          end
        end

        context 'when the required argument has a default value' do
          let(:graphql_type) do
            Class.new(GraphQL::Schema::Object) do
              graphql_name "DummyHashGreeter#{rand(10**9)}"

              field :greeting_for, String, null: false do
                argument :name, String, default_value: 'stranger'
              end

              def greeting_for(name:) = "Hi #{name}"
            end
          end

          it { is_expected.to be_empty }
        end

        context 'when the argument is required but nullable' do
          let(:graphql_type) do
            Class.new(GraphQL::Schema::Object) do
              graphql_name "DummyHashGreeter#{rand(10**9)}"

              field :greeting_for, String, null: false do
                argument :name, String, required: :nullable
              end

              def greeting_for(name:) = "Hi #{name}"
            end
          end

          context 'without arguments' do
            it 'returns error message' do
              expect(error_messages)
                .to eq(['Field "greetingFor" requires arguments name, pass them with `with_arguments`'])
            end
          end

          context 'with a nil argument' do
            let(:matcher) { described_class.new(graphql_type).with_arguments(greeting_for: { name: nil }) }

            it { is_expected.to be_empty }
          end
        end

        context 'when arguments are given in several calls' do
          let(:matcher) do
            described_class.new(graphql_type)
              .with_arguments(greeting_for: { name: 'John' })
              .with_arguments(other_field: { id: 1 })
          end

          it { is_expected.to be_empty }
        end

        context 'when the field name is not camelized' do
          let(:matcher) { described_class.new(graphql_type).with_arguments(greeting_for: { name: 'John' }) }
          let(:graphql_type) do
            Class.new(GraphQL::Schema::Object) do
              graphql_name "DummyHashGreeter#{rand(10**9)}"

              field :greeting_for, String, null: false, camelize: false do
                argument :name, String
              end

              def greeting_for(name:) = "Hi #{name}"
            end
          end

          it { is_expected.to be_empty }
        end
      end

      context 'when an argument with a default value is given' do
        let(:record) { {} }
        let(:graphql_type) do
          Class.new(GraphQL::Schema::Object) do
            graphql_name "DummyEcho#{rand(10**9)}"

            field :echo, String, null: false do
              argument :value, String, default_value: 'default'
            end

            def echo(value:)
              value unless value == 'default'
            end
          end
        end

        context 'without arguments' do
          it 'calls the field with the default value' do
            expect(error_messages).to eq(['expected non-nullable field "echo" not to be `nil`'])
          end
        end

        context 'with arguments' do
          let(:matcher) { described_class.new(graphql_type).with_arguments(echo: { value: 'given' }) }

          it { is_expected.to be_empty }
        end

        context 'with arguments for the same path given twice in different naming' do
          let(:matcher) do
            described_class.new(graphql_type).with_arguments(echo: { value: 'default' }).with_arguments('echo' => {})
              .with_arguments(echo: { value: 'given' })
          end

          it { is_expected.to be_empty }
        end
      end

      context 'when the field name contains an ActiveSupport acronym' do
        let(:record) { {} }
        let(:matcher) { described_class.new(graphql_type).with_arguments(user_api_key: { name: 'John' }) }
        let(:graphql_type) do
          Class.new(GraphQL::Schema::Object) do
            graphql_name "DummyApiKey#{rand(10**9)}"

            field :user_api_key, String, null: false do
              argument :name, String
            end

            def user_api_key(name:) = "key-#{name}"
          end
        end

        around do |example|
          ActiveSupport::Inflector.inflections(:en) { _1.acronym('API') }
          example.run
        ensure
          ActiveSupport::Inflector.inflections(:en).clear(:acronyms)
        end

        it { is_expected.to be_empty }
      end

      context 'when a Hash value is looked up by key' do
        let(:record) { { greeting_for: 'Hi John' } }
        let(:graphql_type) do
          Class.new(GraphQL::Schema::Object) do
            graphql_name "DummyHashGreeting#{rand(10**9)}"

            field :greeting_for, String, null: false do
              argument :name, String
            end
          end
        end

        it { is_expected.to be_empty }
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

    context 'when nested objects lead back to a record already being checked' do
      let(:matcher) { super().tap(&:deeply) }

      let(:graphql_type) do
        Class.new(GraphQL::Schema::Object) do
          graphql_name "DummyPerson#{rand(10**9)}"
          field :id, GraphQL::Types::ID, null: false
          field :name, String, null: false
          field :friends, [self], null: false
        end
      end

      # Built anew on every call, like a decorator wrapping the same record
      let(:person_class) do
        Struct.new(:id, :name, :friend_ids, :people, keyword_init: true) do
          def friends = friend_ids.map { |id| people.fetch(id).dup }
        end
      end

      let(:record) { people.fetch('1') }
      let(:people) do
        {}.tap do |people|
          people['1'] = person_class.new(id: '1', name: 'Ann', friend_ids: %w[2], people:)
          people['2'] = person_class.new(id: '2', name: second_name, friend_ids: %w[1 2], people:)
        end
      end

      context 'when every record matches' do
        let(:second_name) { 'Bob' }

        it { is_expected.to be_empty }
      end

      context 'when a record inside the cycle does not match' do
        let(:second_name) { nil }

        it 'reports it once' do
          expect(error_messages).to eq(['expected non-nullable field "friends[0].name" not to be `nil`'])
        end
      end

      context 'when using shallow mode, which still checks the fields of list items' do
        let(:matcher) { described_class.new(graphql_type).tap(&:shallow) }
        let(:second_name) { 'Bob' }

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

        context 'when nested value is a Hash' do
          let(:location) { { :country => 'USA', 'city' => 'New York' } }

          it { is_expected.to be_empty }
        end

        context 'when nested Hash value does not match' do
          let(:location) { { country: 'USA', city: true } }

          it 'returns error message' do
            expect(error_messages)
              .to eq(['Expected field "location.city" to be one of `[String, Symbol, Numeric, Date, Time]`, ' \
                      'but was `TrueClass`'])
          end
        end

        context 'when nested GraphqlRails type value is a Hash' do
          let(:location_type) do
            Class.new do
              include GraphqlRails::Model

              graphql do |c|
                c.name("DummyLocation#{rand(10**9)}")
                c.attribute(:country).type('String!')
                c.attribute(:city).type('String!')
              end
            end
          end
          let(:location) { { country: 'USA', city: 'New York' } }

          it 'returns error message, as GraphqlRails calls the attribute method on the Hash' do
            expect(error_messages.first).to start_with('Method `country` for "location.country" field does not exist')
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

          context 'when one Hash array item does not match' do
            let(:locations) { [{ 'country' => 'USA', 'city' => 'Kaunas' }, { country: 'USA', city: true }] }

            it 'returns error message' do
              expect(error_messages)
                .to eq(['Expected field "locations[1].city" to be one of `[String, Symbol, Numeric, Date, Time]`, ' \
                     'but was `TrueClass`'])
            end
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
