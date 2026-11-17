pub mod app;
pub mod engine;
pub mod platform;
pub mod settings;
pub mod store;

pub use engine::{Effect, Engine, Phase, Presence, TickInput};
pub use settings::{PillVisibility, Settings};
pub use store::Store;

pub fn run() {
    app::run();
}
