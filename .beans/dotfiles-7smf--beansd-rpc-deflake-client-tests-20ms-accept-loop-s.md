---
# dotfiles-7smf
title: 'beansd-rpc: deflake client tests'' 20ms accept-loop sleep'
status: todo
type: bug
priority: low
created_at: 2026-05-17T12:28:08Z
updated_at: 2026-05-17T12:28:08Z
parent: dotfiles-nzsd
---

Observed once during dotfiles-ls8b smoke-checks: `beansd-rpc::client::tests::empty_response_maps_to_friendly_error` failed in a Nix sandbox build with 22 passed; 1 failed. Could not reproduce in subsequent runs.

The whole `client::tests` module follows this pattern:

```rust
async fn silent_responder(path: &Path) {
    let listener = UnixListener::bind(path).unwrap();
    tokio::spawn(async move {
        while let Ok((_sock, _)) = listener.accept().await {}
    });
}

#[tokio::test]
async fn empty_response_maps_to_friendly_error() {
    let dir = tempdir().unwrap();
    let p = dir.path().join("sock");
    silent_responder(&p).await;
    tokio::time::sleep(Duration::from_millis(20)).await; // <-- racy
    // ... blocking client connect + ls
}
```

The 20ms is a soft guard for "accept loop is running" before the blocking client connects. The kernel will queue connections in the backlog even before `accept()` runs (so connect should not fail outright), but under Nix-sandbox load the timing budget can be tight enough to surface odd behaviours — e.g. the client read returning bytes from a slow connection or seeing a different error string than expected.

`ls_round_trip`, `empty_response_maps_to_friendly_error`, and `malformed_response_maps_to_friendly_error` all share the same pattern.

## Suggested fix

Replace the 20ms sleep with an explicit handshake — e.g. `oneshot::Sender` notified once the accept loop has its first call queued, or simply pre-run one `accept()` to completion before the test blocks. Either removes the timing assumption entirely.

## Acceptance

- [ ] No `tokio::time::sleep` used to wait for the responder to be ready in `client::tests`
- [ ] `cargo test -p beansd-rpc` × 30 iterations passes (locally and in nix sandbox)
