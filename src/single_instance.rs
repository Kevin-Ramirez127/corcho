use std::io::{Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;

use crate::deeplink;

fn socket_path() -> PathBuf {
    if let Some(dir) = std::env::var_os("XDG_RUNTIME_DIR") {
        PathBuf::from(dir).join("corcho.sock")
    } else {
        PathBuf::from(format!("/tmp/corcho-{}.sock", unsafe { libc::getuid() }))
    }
}

/// If another instance owns the socket, forward this process's arguments and
/// return true (the caller should exit). Otherwise bind the socket and start
/// the listener, returning false.
pub fn forward_if_running(args: &[String]) -> bool {
    let path = socket_path();

    if let Ok(mut stream) = UnixStream::connect(&path) {
        let payload = args.join("\n");
        let _ = stream.write_all(payload.as_bytes());
        return true;
    }

    let _ = std::fs::remove_file(&path);
    match UnixListener::bind(&path) {
        Ok(listener) => {
            std::thread::spawn(move || {
                for connection in listener.incoming() {
                    let Ok(mut stream) = connection else { continue };
                    let mut buffer = String::new();
                    if stream.read_to_string(&mut buffer).is_ok() {
                        for line in buffer.lines() {
                            if line.starts_with("corcho://") {
                                deeplink::dispatch(line);
                            }
                        }
                    }
                }
            });
            false
        }
        Err(err) => {
            tracing::warn!("single-instance socket unavailable: {err}");
            false
        }
    }
}
