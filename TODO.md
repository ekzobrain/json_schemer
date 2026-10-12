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
