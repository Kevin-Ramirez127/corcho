use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::symlink;
use std::os::unix::io::AsRawFd;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicI32, Ordering};
use std::time::Duration;

static CRASH_FD: AtomicI32 = AtomicI32::new(-1);
static LOG_FD: AtomicI32 = AtomicI32::new(-1);

fn log_dir() -> PathBuf {
    let dir = crate::storage::default_data_dir().join("logs");
    if fs::create_dir_all(&dir).is_ok() {
        dir
    } else {
        let fallback = PathBuf::from("/tmp/corcho-logs");
        let _ = fs::create_dir_all(&fallback);
        fallback
    }
}

fn link_latest(dir: &Path, target: &Path, name: &str) {
    let link = dir.join(name);
    let _ = fs::remove_file(&link);
    if let Some(file) = target.file_name() {
        let _ = symlink(file, link);
    }
}

pub fn init(redirect_stdout: bool) -> (PathBuf, PathBuf) {
    let dir = log_dir();
    let stamp = time::OffsetDateTime::now_utc().unix_timestamp();
    let log_path = dir.join(format!("corcho-{stamp}.log"));
    let crash_path = dir.join(format!("crash-{stamp}.log"));

    // Print the paths before stdout/stderr are redirected.
    eprintln!("[corcho] log file:    {}", log_path.display());
    eprintln!("[corcho] crash file:  {}", crash_path.display());

    if let Ok(file) = OpenOptions::new().create(true).append(true).open(&log_path) {
        let fd = file.as_raw_fd();
        LOG_FD.store(fd, Ordering::Relaxed);
        if redirect_stdout {
            unsafe {
                libc::dup2(fd, 1);
                libc::dup2(fd, 2);
            }
        }
        std::mem::forget(file);
    }

    let header = format!(
        "=== corcho {} starting pid {} ===\nargs: {:?}\n",
        env!("CARGO_PKG_VERSION"),
        std::process::id(),
        std::env::args().collect::<Vec<_>>()
    );
    eprintln!("{header}");

    if let Ok(file) = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&crash_path)
    {
        let fd = file.as_raw_fd();
        CRASH_FD.store(fd, Ordering::Relaxed);
        std::mem::forget(file);
        unsafe {
            libc::write(fd, header.as_ptr() as *const _, header.len());
        }
    }

    link_latest(&dir, &log_path, "latest.log");
    link_latest(&dir, &crash_path, "latest-crash.log");

    install_panic_hook(crash_path.clone());
    install_signal_handlers();

    (log_path, crash_path)
}

fn install_panic_hook(crash_path: PathBuf) {
    std::panic::set_hook(Box::new(move |info| {
        let backtrace = std::backtrace::Backtrace::force_capture();
        let message = format!("=== PANIC ===\n{info}\n{backtrace}\n");
        if let Ok(mut file) = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&crash_path)
        {
            let _ = file.write_all(message.as_bytes());
            let _ = file.flush();
        }
        eprintln!("{message}");
    }));
}

extern "C" fn crash_handler(signal: libc::c_int) {
    let message: &[u8] = match signal {
        libc::SIGSEGV => b"\n=== CRASH: SIGSEGV (segmentation fault) ===\n",
        libc::SIGABRT => b"\n=== CRASH: SIGABRT (abort) ===\n",
        libc::SIGBUS => b"\n=== CRASH: SIGBUS (bus error) ===\n",
        libc::SIGILL => b"\n=== CRASH: SIGILL (illegal instruction) ===\n",
        libc::SIGFPE => b"\n=== CRASH: SIGFPE (floating point) ===\n",
        _ => b"\n=== CRASH: signal ===\n",
    };
    let fd = CRASH_FD.load(Ordering::Relaxed);
    if fd >= 0 {
        unsafe {
            libc::write(fd, message.as_ptr() as *const _, message.len());
        }
    }
    unsafe {
        libc::signal(signal, libc::SIG_DFL);
        libc::raise(signal);
    }
}

pub fn install_signal_handlers() {
    for signal in [
        libc::SIGSEGV,
        libc::SIGABRT,
        libc::SIGBUS,
        libc::SIGILL,
        libc::SIGFPE,
    ] {
        unsafe {
            libc::signal(signal, crash_handler as extern "C" fn(libc::c_int) as usize);
        }
    }
}

/// Raise SIGSEGV after the UI starts, to verify the crash log pipeline.
pub fn arm_crash_test() {
    std::thread::spawn(|| {
        std::thread::sleep(Duration::from_secs(1));
        unsafe {
            libc::raise(libc::SIGSEGV);
        }
    });
}

fn write_fd(fd: i32, bytes: &[u8]) {
    if fd >= 0 {
        unsafe {
            libc::write(fd, bytes.as_ptr() as *const _, bytes.len());
        }
    }
}

/// Called from the C++ Qt message handler installed by `cpp/qt_logging.cpp`.
#[no_mangle]
pub extern "C" fn corcho_log_message(kind: libc::c_int, message: *const libc::c_char) {
    if message.is_null() {
        return;
    }
    let text = unsafe { std::ffi::CStr::from_ptr(message) }
        .to_string_lossy()
        .to_string();
    let label = match kind {
        0 => "debug",
        1 => "warn",
        2 => "critical",
        3 => "fatal",
        _ => "info",
    };
    let line = format!("[qt/{label}] {text}\n");
    write_fd(LOG_FD.load(Ordering::Relaxed), line.as_bytes());
}
