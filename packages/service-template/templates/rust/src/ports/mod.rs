// "in" is a Rust keyword; alias the directory to `port_in` via #[path]
// so the module tree can still call it something valid.
#[path = "in/mod.rs"]
pub mod port_in;
pub mod out;
