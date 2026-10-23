pub mod analysis;
pub mod benchmark;
mod cache;
mod catalog;
pub mod collect;
mod credentials;
pub mod daily;
pub mod dashen;
#[cfg(any(debug_assertions, feature = "demo"))]
pub mod demo;
mod domain;
mod export;
pub mod growth;
pub mod insights;
pub mod ir;
pub mod maps;
pub mod party;
pub mod progress;
pub mod ranks;
mod report;
mod scheduler;
pub mod stadium;
pub mod stats;
pub mod strength;
pub mod update;
pub use cache::{CachedDetail, ListKey, MemoryCache, RATINGS_TTL, StoredList, StrengthCache};
pub use catalog::*;
pub use credentials::*;
pub use domain::*;
pub use export::*;
pub use progress::{Progress, ProgressSnapshot};
pub use report::*;
pub use scheduler::*;

/// The sample player's name (`demo`). Known even where the sample is left out, so a
/// release build can drop it from a player library made by a development build.
pub const DEMO_NAME: &str = "示例玩家#0000";

/// Whether this build carries the sample player: development builds do, a release build
/// only with `--features demo` (the published package does not).
pub const DEMO_AVAILABLE: bool = cfg!(any(debug_assertions, feature = "demo"));
