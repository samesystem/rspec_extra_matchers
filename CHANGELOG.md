# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
* `be_successful_graphql_request` no longer expects an instance of a `GraphQL::Schema::Object` return type, even one that includes `GraphqlRails::Model`
* `be_successful_graphql_request` treats a `Struct` result as a single object unless the action returns a list, as GraphQL does
* `be_successful_graphql_request` has a `#description`, so one-liner examples get a readable name
