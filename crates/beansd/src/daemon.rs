use crate::registry::Registry;
use crate::spawner::ChildSpawner;
use crate::supervisor::Supervisor;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;

pub struct Daemon<S: ChildSpawner + 'static> {
    pub registry: Arc<Mutex<Registry>>,
    pub supervisor: Arc<Supervisor<S>>,
    pub lru_cap: usize,
    pub sigterm_grace: Duration,
    pub sigkill_grace: Duration,
    pub start_max_attempts: usize,
    pub start_base_backoff: Duration,
}
