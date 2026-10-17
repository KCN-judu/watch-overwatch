#![cfg_attr(target_os = "windows", windows_subsystem = "windows")]
use std::{process::Command, time::Duration};
fn main() {
    let address = "http://127.0.0.1:18180/";
    if std::net::TcpStream::connect_timeout(
        &"127.0.0.1:18180".parse().unwrap(),
        Duration::from_millis(300),
    )
    .is_err()
        && let Ok(exe) = std::env::current_exe()
        && let Some(dir) = exe.parent()
    {
        let mut command = Command::new(dir.join("watchd.exe"));
        command.current_dir(dir);
        #[cfg(target_os = "windows")]
        {
            use std::os::windows::process::CommandExt;
            command.creation_flags(0x08000000);
        }
        if command.spawn().is_err() {
            return;
        }
        for _ in 0..50 {
            if std::net::TcpStream::connect_timeout(
                &"127.0.0.1:18180".parse().unwrap(),
                Duration::from_millis(100),
            )
            .is_ok()
            {
                break;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
    }
    #[cfg(target_os = "windows")]
    if let Err(error) = desktop(address) {
        show_startup_error(&error.to_string());
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = Command::new(if cfg!(target_os = "macos") {
            "open"
        } else {
            "xdg-open"
        })
        .arg(address)
        .spawn();
    }
}

#[cfg(target_os = "windows")]
fn desktop(address: &str) -> anyhow::Result<()> {
    use tao::{
        dpi::LogicalSize,
        event::{Event, WindowEvent},
        event_loop::{ControlFlow, EventLoop},
        window::{Theme, WindowBuilder},
    };
    use wry::{WebContext, WebViewBuilder, WebViewBuilderExtWindows};
    let event_loop = EventLoop::new();
    let window = WindowBuilder::new()
        .with_title("Watch Overwatch")
        .with_theme(Some(Theme::Light))
        .with_inner_size(LogicalSize::new(1440.0, 940.0))
        .with_min_inner_size(LogicalSize::new(820.0, 600.0))
        .build(&event_loop)?;
    neutral_caption(&window);
    let mut context = WebContext::new(Some(watch_core::data_dir().join("webview-profile")));
    let webview = WebViewBuilder::new_with_web_context(&mut context)
        .with_browser_extensions_enabled(false)
        .with_url(address)
        .with_devtools(cfg!(debug_assertions))
        .with_navigation_handler(|url| {
            url == "http://127.0.0.1:18180/" || url == "http://localhost:18180/"
        })
        .with_new_window_req_handler(|url, _| {
            if url.starts_with("https://") {
                let _ = Command::new("rundll32.exe")
                    .args(["url.dll,FileProtocolHandler", &url])
                    .spawn();
            }
            wry::NewWindowResponse::Deny
        })
        .build(&window)?;
    event_loop.run(move |event, _, control_flow| {
        // Keep both the host and its webview alive for the complete event loop.
        let _ = (&window, &webview);
        *control_flow = ControlFlow::Wait;
        if let Event::WindowEvent {
            event: WindowEvent::CloseRequested,
            ..
        } = event
        {
            *control_flow = ControlFlow::Exit;
        }
    });
}

#[cfg(target_os = "windows")]
fn neutral_caption(window: &tao::window::Window) {
    use raw_window_handle::{HasWindowHandle, RawWindowHandle};
    #[link(name = "dwmapi")]
    unsafe extern "system" {
        fn DwmSetWindowAttribute(hwnd: isize, attribute: u32, value: *const u32, size: u32) -> i32;
    }
    if let Ok(handle) = window.window_handle()
        && let RawWindowHandle::Win32(handle) = handle.as_raw()
    {
        // Windows 11 caption/text colours. Unsupported attributes on older Windows are harmless.
        unsafe {
            DwmSetWindowAttribute(handle.hwnd.get(), 35, &0x00ffffff, 4);
            DwmSetWindowAttribute(handle.hwnd.get(), 36, &0x002b2017, 4);
        }
    }
}

#[cfg(target_os = "windows")]
fn show_startup_error(message: &str) {
    #[link(name = "user32")]
    unsafe extern "system" {
        fn MessageBoxW(hwnd: isize, text: *const u16, caption: *const u16, flags: u32) -> i32;
    }
    let text: Vec<u16> =
        format!("无法启动桌面窗口。请确认已安装 Microsoft Edge WebView2 Runtime。\n\n{message}")
            .encode_utf16()
            .chain(Some(0))
            .collect();
    let caption: Vec<u16> = "Watch Overwatch".encode_utf16().chain(Some(0)).collect();
    unsafe {
        MessageBoxW(0, text.as_ptr(), caption.as_ptr(), 0x10);
    }
}
