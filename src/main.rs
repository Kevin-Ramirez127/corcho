mod ai;
mod audio;
mod bridge;
mod core;
mod deeplink;
mod gitsync;
mod history;
mod integrations;
mod mcp;
mod model;
mod search;
mod single_instance;
mod storage;
mod sync;
mod theme;
mod updates;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QUrl};

fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("corcho=info")),
        )
        .init();

    let args: Vec<String> = std::env::args().collect();
    let http_index = args.iter().position(|a| a == "--mcp-http");
    if let Some(index) = http_index {
        let addr = args
            .get(index + 1)
            .cloned()
            .unwrap_or_else(|| "127.0.0.1:7411".to_string());
        if let Err(err) = mcp::serve_http(&addr) {
            eprintln!("mcp http: {err}");
            std::process::exit(1);
        }
        return;
    }
    if args.iter().any(|a| a == "--mcp") || std::env::var("CORCHO_MCP").as_deref() == Ok("1") {
        if let Err(err) = mcp::serve() {
            eprintln!("mcp: {err}");
            std::process::exit(1);
        }
        return;
    }
    if single_instance::forward_if_running(&args) {
        return;
    }

    let mut app = QGuiApplication::new();
    let mut engine = QQmlApplicationEngine::new();

    if let Some(engine) = engine.as_mut() {
        engine.load(&QUrl::from("qrc:/qt/qml/Corcho/qml/Main.qml"));
    }

    if let Some(app) = app.as_mut() {
        app.exec();
    }
}
