use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    let mut qml_files: Vec<std::path::PathBuf> = std::fs::read_dir("qml")
        .expect("qml directory")
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().map(|e| e == "qml").unwrap_or(false))
        .collect();
    qml_files.sort();
    println!("cargo::rerun-if-changed=qml");
    for path in &qml_files {
        println!("cargo::rerun-if-changed={}", path.display());
    }

    CxxQtBuilder::new_qml_module(QmlModule::new("Corcho").qml_files(qml_files))
        .qt_module("Quick")
        .qt_module("QuickControls2")
        .qt_module("Network")
        .qt_module("Svg")
        .qt_module("WebEngineQuick")
        .qrc("resources.qrc")
        .cpp_file("cpp/qt_logging.cpp")
        .cpp_file("cpp/clipboard.cpp")
        .files(["src/bridge.rs"])
        .build();
}
