# TODO

## Read-only hooks: skip transaction copies

Hooks that only inspect data (logging, analytics, collecting values) still pay for transactions inside subschemas that
are only tried (`anyOf`, `oneOf`, `not`, `if`, `contains`): before hooks are called for an object, it is copied
(`Context#record_change`, a shallow `dup` per object per transaction) so that a failed attempt can be rolled back, and
every attempt allocates a `Transaction` (a hash and an array of deferred calls). Whether a hook changes data can't be
detected automatically: the copy has to exist before the hook is called, and freezing the object would make a writing
hook fail halfway.

Measured on a 200 item order with a `oneOf` in every item (`valid?`), compared to running without transactions at all:

| hooks (no-op)        | time             | objects       |
|----------------------|------------------|---------------|
| property hooks only  | 13.7 -> ~11 ms   | 5329 -> ~2529 |
| all hooks            | ~24 -> ~23 ms    | 9541 -> ~6741 |

Without branches there is nothing to gain: transactions are only created by branches, and without hooks they're turned
off entirely (`Context#transactions` is nil).

Possible implementation:
- mark hooks as read-only per hook (eg `JSONSchemer.read_only_hook(proc)`, a wrapper keeping the hook's `parameters`
  and `lambda?` for the arity checks), possibly also with a schema-wide option;
- skip `record_change` (and `sync_instance`) where every hook called for the object is read-only;
- create the transaction hash and the deferred calls array lazily, on the first recorded change or deferred call, so
  that attempts in which nothing was recorded allocate nothing (useful on its own, without read-only hooks).

Limitations to document:
- copies are made once per object per transaction, before the first hook that may change it, and cover changes by all
  later hooks: a read-only `after_value_validation` doesn't help if `before_value_validation` changes data (only
  `sync_instance` after it is skipped). The gain comes only where all hooks called for an object inside a branch are
  read-only (`before_object_validation`, `before/after_property_validation` and value hooks all touch the same object);
- a hook marked read-only that does change data isn't rolled back with a failed attempt.

## Fast path (`valid_instance?`): cover more keywords

`valid?` first tries the fast path (`Schema#validate_instance_boolean` -> `valid_instance?`): no results, no locations,
stops at the first error. It's only used without hooks, `insert_property_defaults` and custom keywords, and gives up
(returns nil) as soon as it meets a keyword without `valid_instance?`, in which case the instance is validated again on
the general path (`flag` output, which no longer builds the result tree, see `Context#result_tree`). The work done
before giving up is wasted, so a single unsupported keyword deep in the schema makes `valid?` slower than the general
path alone.

Measured on the 200 item order of `test/performance/hooks_benchmark.rb` without `format` (so that the fast path is
used), `valid?`: fast path 3.5-3.9 ms / 3211 objects, general `flag` path 7.7-8.7 ms / 2415 objects.

Keywords without `valid_instance?` (fall back to the general path):
- `format` (draft 2020-12 annotation and assertion vocabularies) - the most common one; with the benchmark's `format`
  keywords `valid?` always takes the general path;
- `if`/`then`/`else`, `dependentSchemas`, `dependencies`, `dependentRequired`;
- `patternProperties`, `propertyNames`;
- `contains`, `minContains`, `maxContains`;
- `readOnly`, `writeOnly` (`access_mode`);
- `unevaluatedItems`, `unevaluatedProperties` (need annotations of adjacent and nested keywords: probably stay on the
  general path, or need a light annotation collection);
- `contentEncoding`, `contentMediaType`, `contentSchema`;
- draft 4 `exclusiveMaximum`/`exclusiveMinimum`, draft 2019-09 `items`/`additionalItems`/`$recursiveRef`/
  `$recursiveAnchor`, draft 7 `additionalItems`;
- OpenAPI 3.1 `anyOf`/`oneOf`/`discriminator` (return nil explicitly).

Other points:
- `Schema#valid_instance?` allocates an `adjacent_results` hash for every schema (that's why it allocates more than the
  general path); use `collect_adjacent_results?` / `NO_ADJACENT_RESULTS` like the general path;
- check whether the fallback can be avoided up front: compute once per schema (memoized, recursively through
  subschemas and `$ref`s, with care for cycles) whether the fast path supports it, instead of discovering it during
  validation;
- consider whether both paths are worth keeping at all if the general `flag` path gets close enough;
- every keyword implemented on the fast path must agree with the general path: run JSON-Schema-Test-Suite through both
  (eg assert `validate_instance_boolean` == `validate(output_format: 'flag')` where the former isn't nil).

## OpenAPI `discriminator`: don't change the validation outcome

OpenAPI 3.1.0 allowed `discriminator` to "act as a hint to shortcut validation and selection of the matching schema",
but 3.1.1, 3.1.2 and 3.2.0 say "discriminator MUST NOT change the validation outcome of the schema". The OpenAPI 3.1 and
3.2 vocabularies (`OpenAPI31::Vocab::Base`, `OpenAPI32::Vocab::Base::Discriminator`) still replace `anyOf`/`oneOf`
with the schema selected by the discriminating property, which changes the outcome:
- `oneOf` with an instance matching several subschemas is valid if the discriminated one matches (JSON Schema: invalid);
- an instance without the discriminating property, or with a value without a mapping (and without `defaultMapping` in
  3.2), is invalid even if `anyOf`/`oneOf` would match;
- with the `allOf` form, validating the parent schema validates the child schema selected by the discriminating
  property, while the specification says the parent "does not perform a search for child schemas or use them in
  validation in any way".

Possible change: evaluate `anyOf`/`oneOf`/`allOf` as plain JSON Schema and use `discriminator` only to pick the subschema
whose errors are reported (and as an annotation), keeping the current behavior for OpenAPI 3.1.0 / 3.0 documents or
behind an option, since it is a breaking change for existing users. `defaultMapping` would then only affect which
errors are reported.
