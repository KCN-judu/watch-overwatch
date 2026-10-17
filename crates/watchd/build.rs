//! Embeds the application icon in the Windows executables of this package, so the
//! local service and the launcher do not show the generic default icon.
//! Uses `rc.exe` from the Windows SDK; without it the build still succeeds, just
//! without the icon.
use std::{env, fs, path::PathBuf, process::Command};

fn find_rc() -> Option<PathBuf> {
    if let Ok(p) = env::var("RC") {
        let p = PathBuf::from(p);
        if p.exists() {
            return Some(p);
        }
    }
    let base = PathBuf::from(r"C:\Program Files (x86)\Windows Kits\10\bin");
    let mut versions: Vec<PathBuf> = fs::read_dir(&base)
        .ok()?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.join("x64").join("rc.exe").exists())
        .collect();
    versions.sort();
    versions.pop().map(|p| p.join("x64").join("rc.exe"))
}

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=assets/app.ico");
    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("windows") {
        return;
    }
    let out = PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR"));
    let icon = PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("manifest dir"))
        .join("assets")
        .join("app.ico");
    let Some(rc) = find_rc() else {
        println!("cargo:warning=rc.exe not found; executables will have no embedded icon");
        return;
    };
    let script = out.join("icon.rc");
    let res = out.join("icon.res");
    // Backslashes must be doubled inside an .rc string.
    let icon_path = icon.to_string_lossy().replace("\\", "\\\\");
    if fs::write(&script, format!("1 ICON \"{icon_path}\"\n")).is_err() {
        return;
    }
    let status = Command::new(&rc)
        .args(["/nologo", "/fo"])
        .arg(&res)
        .arg(&script)
        .status();
    match status {
        Ok(s) if s.success() => {
            println!("cargo:rustc-link-arg-bins={}", res.display());
        }
        _ => println!("cargo:warning=rc.exe failed; executables will have no embedded icon"),
    }
}
