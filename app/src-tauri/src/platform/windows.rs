use super::Platform;
use crate::engine::Presence;
use windows::Win32::Foundation::{CloseHandle, HANDLE, HWND};
use windows::Win32::System::Diagnostics::ToolHelp::{
    CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, PROCESSENTRY32W, TH32CS_SNAPPROCESS,
};
use windows::Win32::System::RemoteDesktop::{
    WTSFreeMemory, WTSQuerySessionInformationW, WTS_CURRENT_SESSION, WTS_SESSIONSTATE_LOCK,
    WTSSessionInfoEx, WTSINFOEXW,
};
use windows::Win32::System::SystemInformation::GetTickCount;
use windows::Win32::UI::Input::KeyboardAndMouse::{GetLastInputInfo, LASTINPUTINFO};
use windows::Win32::UI::Shell::{
    SHQueryUserNotificationState, QUNS_BUSY, QUNS_RUNNING_D3D_FULL_SCREEN,
};
use windows::Win32::UI::WindowsAndMessaging::{
    GetWindowLongPtrW, SetWindowLongPtrW, SetWindowPos, GWL_EXSTYLE, HWND_TOPMOST,
    SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOSIZE, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW,
};

#[derive(Default)]
pub struct WindowsPlatform;

const ANTI_CHEAT: &[&str] = &[
    "vgc.exe",
    "vgtray.exe",
    "easyanticheat.exe",
    "easyanticheat_eos.exe",
    "beservice.exe",
    "faceit.exe",
    "faceitservice.exe",
    "gamemon.des",
    "gamemon64.des",
    "xhunter1.exe",
];

impl Platform for WindowsPlatform {
    fn idle_seconds(&self) -> f64 {
        unsafe {
            let mut info = LASTINPUTINFO {
                cbSize: std::mem::size_of::<LASTINPUTINFO>() as u32,
                dwTime: 0,
            };
            if GetLastInputInfo(&mut info).as_bool() {
                let now = GetTickCount();
                return now.wrapping_sub(info.dwTime) as f64 / 1000.0;
            }
            0.0
        }
    }

    fn locked(&self) -> bool {
        unsafe {
            let mut buffer = windows::core::PWSTR::null();
            let mut returned = 0u32;
            let ok = WTSQuerySessionInformationW(
                HANDLE::default(),
                WTS_CURRENT_SESSION,
                WTSSessionInfoEx,
                &mut buffer,
                &mut returned,
            )
            .is_ok();
            if !ok || buffer.is_null() {
                return false;
            }
            let locked = if returned as usize >= std::mem::size_of::<WTSINFOEXW>() {
                let info = &*(buffer.0 as *const WTSINFOEXW);
                info.Level == 1
                    && info.Data.WTSInfoExLevel1.SessionFlags == WTS_SESSIONSTATE_LOCK as i32
            } else {
                false
            };
            WTSFreeMemory(buffer.0 as *mut _);
            locked
        }
    }

    fn in_call(&self) -> bool {
        // Windows call detection is out of scope for the first version.
        false
    }

    fn face_present(&self) -> Presence {
        Presence::Unknown
    }

    fn fullscreen_active(&self) -> bool {
        unsafe {
            SHQueryUserNotificationState()
                .map(|state| state == QUNS_RUNNING_D3D_FULL_SCREEN || state == QUNS_BUSY)
                .unwrap_or(false)
        }
    }

    fn anti_cheat_running(&self) -> bool {
        unsafe {
            let snapshot = match CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) {
                Ok(handle) => handle,
                Err(_) => return false,
            };
            let mut entry: PROCESSENTRY32W = std::mem::zeroed();
            entry.dwSize = std::mem::size_of::<PROCESSENTRY32W>() as u32;
            let mut found = false;
            if Process32FirstW(snapshot, &mut entry).is_ok() {
                loop {
                    let name = String::from_utf16_lossy(&entry.szExeFile)
                        .trim_end_matches('\0')
                        .to_lowercase();
                    if ANTI_CHEAT.iter().any(|watched| name == *watched) {
                        found = true;
                        break;
                    }
                    if Process32NextW(snapshot, &mut entry).is_err() {
                        break;
                    }
                }
            }
            let _ = CloseHandle(snapshot);
            found
        }
    }

    fn style_overlay(&self, hwnd: isize) {
        unsafe {
            let handle = HWND(hwnd as *mut _);
            let style = GetWindowLongPtrW(handle, GWL_EXSTYLE);
            let extended = style
                | (WS_EX_NOACTIVATE.0 as isize)
                | (WS_EX_TOOLWINDOW.0 as isize);
            SetWindowLongPtrW(handle, GWL_EXSTYLE, extended);
            self.keep_topmost(hwnd);
        }
    }

    fn keep_topmost(&self, hwnd: isize) {
        unsafe {
            let handle = HWND(hwnd as *mut _);
            let _ = SetWindowPos(
                handle,
                HWND_TOPMOST,
                0,
                0,
                0,
                0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE,
            );
        }
    }
}
