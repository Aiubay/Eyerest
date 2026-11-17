use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::engine::DateKey;
use crate::settings::Settings;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Store {
    #[serde(default)]
    pub settings: Settings,
    #[serde(default)]
    pub history: BTreeMap<DateKey, u32>,
}

impl Store {
    pub fn load(path: &Path) -> Store {
        let store: Store = fs::read_to_string(path)
            .ok()
            .and_then(|text| serde_json::from_str(&text).ok())
            .unwrap_or_default();
        Store {
            settings: store.settings.sanitized(),
            history: store.history,
        }
    }

    pub fn save(&self, path: &Path) -> io::Result<()> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let json = serde_json::to_string_pretty(self)?;
        fs::write(path, json)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_settings_and_history() {
        let path = std::env::temp_dir().join(format!("eyerule-store-{}.json", std::process::id()));
        let mut store = Store::default();
        store.settings.work_minutes = 25;
        store.history.insert(20_000, 7);

        store.save(&path).unwrap();
        let loaded = Store::load(&path);
        let _ = fs::remove_file(&path);

        assert_eq!(loaded.settings.work_minutes, 25);
        assert_eq!(loaded.history.get(&20_000), Some(&7));
    }

    #[test]
    fn missing_file_gives_defaults() {
        let path = std::env::temp_dir().join("eyerule-store-does-not-exist.json");
        let store = Store::load(&path);
        assert_eq!(store.settings.work_minutes, 20);
        assert!(store.history.is_empty());
    }
}
