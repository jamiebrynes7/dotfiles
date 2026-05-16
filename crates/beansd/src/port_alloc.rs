use std::net::TcpListener;

/// Pick an ephemeral loopback port by asking the kernel and immediately
/// dropping the listener. Returns the port the kernel chose.
pub fn pick_loopback_port() -> std::io::Result<u16> {
    let listener = TcpListener::bind("127.0.0.1:0")?;
    let port = listener.local_addr()?.port();
    drop(listener);
    Ok(port)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn picks_a_nonzero_port() {
        let p = pick_loopback_port().unwrap();
        assert!(p > 0);
    }
}
