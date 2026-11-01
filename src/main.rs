mod ai;
mod audio;
mod bridge;
mod core;
mod deeplink;
mod gitsync;
mod history;
mod integrations;
mod model;
mod search;
mod single_instance;
mod storage;
mod sync;
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
