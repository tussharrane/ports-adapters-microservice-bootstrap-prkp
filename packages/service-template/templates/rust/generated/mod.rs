// TODO: this only includes the one existing `Example` message. Adding a
// second proto package will need a nested `mod example { mod ... }` tree
// here instead of a flat include!, since multiple flat includes would
// collide on same-named types in one namespace.
include!("example/v1/example.v1.rs");
