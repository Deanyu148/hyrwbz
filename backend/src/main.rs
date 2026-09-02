// Windows release 模式使用 GUI 子系统，不显示控制台窗口。
#![cfg_attr(
    all(target_os = "windows", not(debug_assertions)),
    windows_subsystem = "windows"
)]

mod db;
mod excel;
mod import_export;
mod models;
mod notifications;
mod rpc;
mod service;

/// 解析 --socket-path 与 --parent-pid。
fn parse_args() -> anyhow::Result<(String, u32)> {
    let mut args = std::env::args().skip(1);
    let mut socket_path = None;
    let mut parent_pid = 0u32;
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--socket-path" => socket_path = args.next(),
            "--parent-pid" => {
                parent_pid = args
                    .next()
                    .and_then(|value| value.parse().ok())
                    .unwrap_or(0);
            }
            _ => {}
        }
    }
    let socket_path = socket_path.ok_or_else(|| anyhow::anyhow!("missing --socket-path"))?;
    Ok((socket_path, parent_pid))
}

#[cfg(windows)]
fn parent_alive(pid: u32) -> bool {
    use windows_sys::Win32::Foundation::CloseHandle;
    use windows_sys::Win32::System::Threading::{GetExitCodeProcess, OpenProcess};
    let handle = unsafe { OpenProcess(0x1000, 0, pid) };
    if handle.is_null() {
        return false;
    }
    let mut code = 0u32;
    let ok = unsafe { GetExitCodeProcess(handle, &mut code) };
    unsafe { CloseHandle(handle) };
    ok != 0 && code == 259
}

#[cfg(not(windows))]
fn parent_alive(pid: u32) -> bool {
    std::path::Path::new(&format!("/proc/{pid}")).exists()
}

async fn parent_watchdog(parent_pid: u32) {
    loop {
        tokio::time::sleep(std::time::Duration::from_secs(1)).await;
        if !parent_alive(parent_pid) {
            std::process::exit(0);
        }
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    #[cfg(debug_assertions)]
    tracing_subscriber::fmt().with_env_filter("info").init();

    let (socket_path, parent_pid) = parse_args()?;
    if parent_pid > 0 {
        tokio::spawn(parent_watchdog(parent_pid));
    }
    let pool = db::init(&db::default_db_path()).await?;
    let notification_store = notifications::NotificationStore::open().await?;
    let notification_store_for_refresh = notification_store.clone();
    let pool_for_refresh = pool.clone();
    tokio::spawn(async move {
        loop {
            if let Err(error) = notification_store_for_refresh.refresh(&pool_for_refresh).await {
                #[cfg(debug_assertions)]
                tracing::warn!("notification refresh failed: {}", error);
            }
            tokio::time::sleep(notifications::REFRESH_INTERVAL).await;
        }
    });
    #[cfg(debug_assertions)]
    tracing::info!("listening on local socket {}", socket_path);
    rpc::serve(&socket_path, pool, notification_store).await
}
