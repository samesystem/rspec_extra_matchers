# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

* `DateTime` and `Date` fields are validated with `coerce_result`, as GraphQL serializes them: a `DateTime` field accepts a `Date` and a well-formatted `String`, and a `Date` field accepts a `Time`. `Date` fields are as lenient as GraphQL: anything whose `to_s` parses as a date passes, such as the Integer `20240101`. Other built-in scalars keep their class checks, since their `coerce_result` accepts almost any value
* `be_successful_graphql_request` sets a `GraphqlRails::Model`'s `graphql_context` to the request's hash-like test context while calling fields of types GraphqlRails built, as GraphqlRails does at runtime, so decorators that read it with `[]`/`fetch` no longer fail. Needs a graphql_rails whose RSpec controller helpers have `response.context`; with an older one fields still run without a context
* `TypeMatcher.new` takes an optional `graphql_context:` for the same purpose
* `be_successful_graphql_request` accepts a record sharing the declared model's ActiveRecord `base_class`, at the top level and in nested fields, since an STI record is served as its own subclass and GraphQL serializes it with the declared type

## [1.0.0] - 2026-10-14

### Fixed

* `be_successful_graphql_request` passes for empty lists, nullable `nil` results and nullable `nil` list items
* `be_successful_graphql_request` checks every list item, not only the first one, and reports the failing index
* Custom scalars are validated with `coerce_result` instead of crashing with `NameError`
* Union types are resolved to their member type instead of crashing
* Lists of enums no longer crash
* Private resolver methods are accepted, matching how GraphqlRails calls them
* `String` fields accept `Symbol`, `Date` and `Time` values, and `ID` fields accept `Symbol` values, as GraphQL serializes them
* Hash results and nested Hash values are resolved by key when the type has no resolver method for the field, as GraphQL resolves them: a missing key is `nil` even when the Hash has a default value. `GraphqlRails::Model` types still reject a Hash, since their resolvers call the attribute method. Fields with `hash_key:`, `dig:` or `fallback_value:` options are not supported yet
* Scalar and enum return types are validated instead of crashing with `NoMethodError`
* Hash fields with a resolver method on their type, such as `def error = object[:errors].first`, are resolved through that method, as GraphQL does, instead of being reported as missing. The method is called without arguments and with an empty query context
* `be_successful_graphql_request` no longer expects an instance of a `GraphQL::Schema::Object` return type, even one that includes `GraphqlRails::Model`
* `be_successful_graphql_request` treats a `Struct` result as a single object unless the action returns a list, as GraphQL does
* `be_successful_graphql_request` has a `#description`, so one-liner examples get a readable name
