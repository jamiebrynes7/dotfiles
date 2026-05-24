use crate::daemon::Daemon;
use crate::registry::Registry;
use crate::supervisor::test_utils::FakeSupervisor;
use crate::web::State;
use std::sync::Arc;
use tokio::sync::Mutex;

pub(in crate::web) fn build_state(registry: Arc<Mutex<Registry>>) -> State {
    let supervisor = FakeSupervisor::new(registry.clone());
    let daemon = Arc::new(Daemon {
        registry: registry.clone(),
        supervisor,
        lru_cap: 8,
    });
    State { registry, daemon }
}

pub(in crate::web) fn empty_state() -> State {
    build_state(Arc::new(Mutex::new(Registry::new())))
}
