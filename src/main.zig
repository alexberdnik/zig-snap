const std = @import("std");
const WINAPI = std.os.windows.WINAPI;

const math = std.math;

const win32 = struct {
    usingnamespace @import("win32").zig;
    usingnamespace @import("win32").foundation;
    usingnamespace @import("win32").system.system_services;
    usingnamespace @import("win32").ui.windows_and_messaging;
    usingnamespace @import("win32").ui.input.keyboard_and_mouse;
    usingnamespace @import("win32").graphics.gdi;
    usingnamespace @import("win32").graphics.dwm;
    usingnamespace @import("win32").system.threading;
};

const RECT = win32.RECT;

const HOT_KEY = enum(i32) {
    LEFT = 1000,
    RIGHT = 1001,
    UP = 1002,
    DOWN = 1003
};

const zones = [_]RECT {
    RECT {.left = 0,    .top = 0,   .right = 1079, .bottom = 784},
    RECT {.left = 0,    .top = 785, .right = 1079, .bottom = 1570},
    RECT {.left = 1080, .top = 0,   .right = 2759, .bottom = 1570},
    RECT {.left = 2760, .top = 0,   .right = 3840, .bottom = 784},
    RECT {.left = 2760, .top = 785, .right = 3840, .bottom = 1570}
};

pub export fn WinMainCRTStartup() callconv(@import("std").os.windows.WINAPI) void {
    registerHotKeys();
    runMessageLoop();
}

fn registerHotKeys() void {
    registerHotKey(HOT_KEY.LEFT, win32.VK_LEFT);
    registerHotKey(HOT_KEY.RIGHT, win32.VK_RIGHT);
    registerHotKey(HOT_KEY.UP, win32.VK_UP);
    registerHotKey(HOT_KEY.DOWN, win32.VK_DOWN);
}

fn registerHotKey(id: HOT_KEY, key: win32.VIRTUAL_KEY) void {
    if(win32.RegisterHotKey(
        null, 
        @enumToInt(id),
        win32.HOT_KEY_MODIFIERS.initFlags(.{.ALT = 1, .CONTROL = 1, .NOREPEAT = 1, .WIN = 1}),
        @enumToInt(key)) == 0) {
        win32.ExitProcess(255);
    }
}

fn runMessageLoop() void {
    var msg : win32.MSG = undefined;
    while (win32.GetMessage(&msg, null, 0, 0) != 0) {
        _ = win32.TranslateMessage(&msg);
        processMessage(&msg);
    }
}

fn processMessage(msg: *win32.MSG) void {
    if (msg.message == win32.WM_HOTKEY) {
        switch(msg.wParam) {
            @enumToInt(HOT_KEY.LEFT),
            @enumToInt(HOT_KEY.RIGHT),
            @enumToInt(HOT_KEY.UP),
            @enumToInt(HOT_KEY.DOWN) => {
                snapActiveWindow(@intToEnum(HOT_KEY, msg.wParam));
            },
            else => {
            }
        }
    }
}

fn snapActiveWindow(key: HOT_KEY) void {
    const hWnd = win32.GetForegroundWindow() orelse return;
    snapWindow(key, hWnd);
}

fn snapWindow(key: HOT_KEY, hWnd: win32.HWND) void {
    var placement: win32.WINDOWPLACEMENT = undefined;
    placement.length = @sizeOf(win32.WINDOWPLACEMENT);
    _ = win32.GetWindowPlacement(hWnd, &placement);
    const maximized = placement.showCmd == win32.SW_SHOWMAXIMIZED;
    const minimized = placement.showCmd == win32.SW_SHOWMINIMIZED;
    const inNormalState = !maximized and !minimized;
    const rect = ajustWindowSizeExcludeBorder(hWnd, placement.rcNormalPosition);
    switch (key) {
        .UP => {
            toggleMaximize(maximized, hWnd);
        },
        .DOWN => {
            toggleMinimize(minimized, hWnd);
        },
        .LEFT => {
            if (inNormalState) {
                snapLeft(hWnd, rect);
            } else {
                restoreWindow(maximized, minimized, hWnd);
            }
        },
        .RIGHT => {
            if (inNormalState) {
                snapRight(hWnd, rect);
            } else {
                restoreWindow(maximized, minimized, hWnd);
            }
        }
    }
}

fn toggleMaximize(maximized: bool, hWnd: win32.HWND) void {
    const state = if (maximized) win32.SW_SHOWNORMAL else win32.SW_SHOWMAXIMIZED;
    _ = win32.ShowWindow(hWnd, state);
}

fn toggleMinimize(minimized: bool, hWnd: win32.HWND) void {
    const state = if (minimized) win32.SW_RESTORE else win32.SW_SHOWMINIMIZED;
    _ = win32.ShowWindow(hWnd, state);
}

fn restoreWindow(maximized: bool, minimized: bool, hWnd: win32.HWND) void {
    if (maximized) {
        _ = win32.ShowWindow(hWnd, win32.SW_SHOWNORMAL);
    }
    if (minimized) {
        _ = win32.ShowWindow(hWnd, win32.SW_RESTORE);
    }
}

fn snapLeft(hWnd: win32.HWND, rect: RECT) void {
    const zoneIndex = findZoneIndex(rect);
    const newZone = zones[if (zoneIndex > 0) zoneIndex - 1 else zones.len - 1];
    moveWindowTo(hWnd, newZone);
}

fn snapRight(hWnd: win32.HWND, rect: RECT) void {
    const zoneIndex = findZoneIndex(rect);
    const newZone = zones[if (zoneIndex + 1 == zones.len) 0 else zoneIndex + 1];
    moveWindowTo(hWnd, newZone);
}

fn findZoneIndex(rect: RECT) usize {
    for (zones) |zone, i| {
        if (isInZone(zone, rect.top, rect.left)) {
            return i;
        }
    }
    return 0;
}

fn isInZone(rect: RECT, top: i32, left: i32) bool {
    return rect.left <= left and left <= rect.right
        and rect.top <= top and top <= rect.bottom;
}

fn moveWindowTo(hWnd: win32.HWND, zone: RECT) void {
    var placement: win32.WINDOWPLACEMENT = undefined;
    placement.length = @sizeOf(win32.WINDOWPLACEMENT);
    _ = win32.GetWindowPlacement(hWnd, &placement);

    placement.flags = win32.WPF_ASYNCWINDOWPLACEMENT;
    placement.showCmd = win32.SW_SHOWNORMAL;
    placement.rcNormalPosition = ajustWindowSizeIncludeBorder(hWnd, zone);
    
    // do it twice like in powertoys
    _ = win32.SetWindowPlacement(hWnd, &placement);
    _ = win32.SetWindowPlacement(hWnd, &placement);
}

fn ajustWindowSizeIncludeBorder(hWnd: win32.HWND, rect: RECT) RECT {
    var newWindowRect = rect;
    var windowRect: RECT = undefined;
    _ = win32.GetWindowRect(hWnd, &windowRect);

    // Take care of borders
    var frameRect: RECT = undefined;
    if (win32.DwmGetWindowAttribute(hWnd, win32.DWMWA_EXTENDED_FRAME_BOUNDS, &frameRect, @sizeOf(RECT)) == win32.S_OK) {
        const leftMargin = frameRect.left - windowRect.left;
        const rightMargin = frameRect.right - windowRect.right;
        const bottomMargin = frameRect.bottom - windowRect.bottom;
        newWindowRect.left -= leftMargin;
        newWindowRect.right -= rightMargin;
        newWindowRect.bottom -= bottomMargin;
    }

    // Take care of windows that cannot be resized
    const winInfo = win32.GetWindowLong(hWnd, win32.GWL_STYLE);
    if ((winInfo & @enumToInt(win32.WS_SIZEBOX)) == 0) {
        newWindowRect.right = newWindowRect.left + (windowRect.right - windowRect.left);
        newWindowRect.bottom = newWindowRect.top + (windowRect.bottom - windowRect.top);
    }

    return newWindowRect;
}

fn ajustWindowSizeExcludeBorder(hWnd: win32.HWND, rect: RECT) RECT {
    var newWindowRect = rect;
    // Take care of borders
    var frameRect: RECT = undefined;
    if (win32.DwmGetWindowAttribute(hWnd, win32.DWMWA_EXTENDED_FRAME_BOUNDS, &frameRect, @sizeOf(RECT)) == win32.S_OK) {
        const leftMargin = frameRect.left - rect.left;
        const rightMargin = frameRect.right - rect.right;
        const bottomMargin = frameRect.bottom - rect.bottom;
        newWindowRect.left += leftMargin;
        newWindowRect.right += rightMargin;
        newWindowRect.bottom += bottomMargin;
    }

    return newWindowRect;
}
