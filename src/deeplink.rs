use std::sync::{Mutex, OnceLock};

use cxx_qt_lib::QString;

pub type QtThread = cxx_qt::CxxQtThread<crate::bridge::qobject::AppController>;

static THREAD: OnceLock<Mutex<Option<QtThread>>> = OnceLock::new();

/// Store the Qt thread once the QML object exists, so the socket thread can
/// deliver deep links onto the GUI thread.
pub fn register(thread: QtThread) {
    let slot = THREAD.get_or_init(|| Mutex::new(None));
    if let Ok(mut guard) = slot.lock() {
        *guard = Some(thread);
    }
}

pub fn is_registered() -> bool {
    THREAD
        .get()
        .and_then(|slot| slot.lock().ok())
        .map(|guard| guard.is_some())
        .unwrap_or(false)
}

pub fn dispatch(url: &str) {
    let url = url.to_string();
    if let Some(slot) = THREAD.get() {
        if let Ok(guard) = slot.lock() {
            if let Some(thread) = guard.as_ref() {
                let _ = thread.queue(move |mut q| {
                    q.as_mut().handle_deep_link(&QString::from(url));
                });
            }
        }
    }
}
