#Requires AutoHotkey v2.0
#SingleInstance Force


; CenterWindow.ahk
; ----------------
; A lightweight window control tool for multi-monitor setups.
;
; Hotkeys:
;
; Mouse4 (XButton1)
; -> Smart restore/maximize toggle
;    - If window is fullscreen (exampple: Youtube/Twitch): exits fullscreen safely
;    - If just exited fullscreen: maximizes window
;    - Otherwise: toggles maximize / restore
;    - Does NOT steal focus
;
; Mouse5 (XButton2)
; -> Move window to next monitor while preserving usable state
;    - Restored/normal -> moves to next monitor and stays restored
;    - Maximized -> moves to next monitor and stays maximized
;    - Does NOT steal focus
;
; Shift + Mouse5
; -> Center window on current monitor
;
; Game Safety:
; -> All hotkeys are bypassed when a game is active (CS2, Valorant, WoW, etc.)
; -> Mouse buttons behave normally inside games
;
; --------------------------



; System setup
; ------------
if !A_IsAdmin {
    try {
        Run '*RunAs "' A_ScriptFullPath '"'
    }
    ExitApp
}

ProcessSetPriority("AboveNormal")

; Track windows I just exited fullscreen on (Mouse4 logic)
global FullscreenJustExited := Map()


; Hotkeys (mouse)
; ---------------
*XButton1::HandleMouse4()
*XButton2::HandleMouse5(true)
*+XButton2::HandleMouse5(false)


; Mouse handlers
; --------------
HandleMouse4() {
    prevActive := WinExist("A")

    hwnd := GetHoveredTopLevelWindowOrActive()
    if !hwnd
        return

    if IsGameWindowHwnd(hwnd) || IsGameWindowHwnd(prevActive) {
        Send "{Blind}{XButton1}"
        return
    }

    ToggleRestoreMaximize_NoFocus_WithFullscreen(hwnd, prevActive)
}

HandleMouse5(isMove) {
    prevActive := WinExist("A")

    hwnd := GetHoveredTopLevelWindowOrActive()
    if !hwnd
        return

    if IsGameWindowHwnd(hwnd) || IsGameWindowHwnd(prevActive) {
        Send "{Blind}{XButton2}"
        return
    }

    ; Shift+Mouse5 → center on current monitor
    if !isMove {
        CenterWindowOnItsMonitor(hwnd)
        return
    }

    ; Mouse5 → move to next monitor while preserving restored/maximized state
    MoveWindowToNextMonitorPreserveState(hwnd, prevActive)
}

MoveWindowToNextMonitorPreserveState(hwnd, prevActive) {
    count := MonitorGetCount()
    if (count < 2)
        return

    mm := 0
    try {
        mm := WinGetMinMax("ahk_id " hwnd)
    } catch {
        mm := 0
    }

    cur := GetMonitorIndexOfWindow(hwnd)
    target := (cur = count) ? 1 : (cur + 1)

    ; Maximized -> restore, move, maximize again
    if (mm = 1) {
        try {
            WinRestore("ahk_id " hwnd)
        } catch {
        }

        CenterWindowOnMonitor(hwnd, target)

        try {
            WinMaximize("ahk_id " hwnd)
        } catch {
        }

        if (prevActive && WinExist("A") != prevActive) {
            try {
                WinActivate("ahk_id " prevActive)
            } catch {
            }
        }
        return
    }

    ; Restored / normal -> move to next monitor + center
    CenterWindowOnMonitor(hwnd, target)

    if (prevActive && WinExist("A") != prevActive) {
        try {
            WinActivate("ahk_id " prevActive)
        } catch {
        }
    }
}


; Hovered window detection
; ------------------------
GetHoveredTopLevelWindowOrActive() {
    MouseGetPos(, , &rawHwnd)
    if !rawHwnd
        return WinExist("A")

    hwnd := GetTopLevelHwnd(rawHwnd)
    if !hwnd
        hwnd := rawHwnd

    cls := ""
    try {
        cls := WinGetClass("ahk_id " hwnd)
    } catch {
        cls := ""
    }

    if (cls = "Shell_TrayWnd" || cls = "WorkerW" || cls = "Progman")
        return WinExist("A")

    return hwnd
}

GetTopLevelHwnd(hwnd) {
    try {
        return DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr")
    } catch {
        return 0
    }
}


; Mouse4 logic
; ------------
ToggleRestoreMaximize_NoFocus_WithFullscreen(hwnd, prevActive) {
    global FullscreenJustExited

    if IsTrueFullscreenWindow(hwnd) {
        try {
            WinActivate("ahk_id " hwnd)
        } catch {
            return
        }

        Sleep 40
        Send "{F11}"
        Sleep 80
        Send "{Esc}"
        Sleep 80

        try {
            WinRestore("ahk_id " hwnd)
        } catch {
        }

        FullscreenJustExited[hwnd] := true

        if (prevActive && WinExist("A") != prevActive) {
            try {
                WinActivate("ahk_id " prevActive)
            } catch {
            }
        }

        return
    }

    if FullscreenJustExited.Has(hwnd) {
        mm := 0
        try {
            mm := WinGetMinMax("ahk_id " hwnd)
        } catch {
            mm := 0
        }

        if (mm != 1) {
            try {
                WinMaximize("ahk_id " hwnd)
            } catch {
            }
        }

        FullscreenJustExited.Delete(hwnd)

        if (prevActive && WinExist("A") != prevActive) {
            try {
                WinActivate("ahk_id " prevActive)
            } catch {
            }
        }

        return
    }

    mm := 0
    try {
        mm := WinGetMinMax("ahk_id " hwnd)
    } catch {
        mm := 0
    }

    if (mm = 1) {
        try {
            WinRestore("ahk_id " hwnd)
        } catch {
        }
    } else {
        try {
            WinMaximize("ahk_id " hwnd)
        } catch {
        }
    }

    if (prevActive && WinExist("A") != prevActive) {
        try {
            WinActivate("ahk_id " prevActive)
        } catch {
        }
    }
}

IsTrueFullscreenWindow(hwnd) {
    try {
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
    } catch {
        return false
    }

    mm := 0
    try {
        mm := WinGetMinMax("ahk_id " hwnd)
    } catch {
        return false
    }

    if (mm = -1)
        return false

    mon := GetMonitorIndexOfWindow(hwnd)
    MonitorGet(mon, &l, &t, &r, &b)

    tol := 2
    return (Abs(x - l) <= tol
        && Abs(y - t) <= tol
        && Abs((x + w) - r) <= tol
        && Abs((y + h) - b) <= tol)
}


; Game detection
; --------------
IsGameWindowHwnd(hwnd) {
    if !hwnd
        return false

    try {
        proc := StrLower(WinGetProcessName("ahk_id " hwnd))
    } catch {
        return false
    }

    return (proc = "cs2.exe"
        || proc = "valorant-win64-shipping.exe"
        || proc = "wowclassic.exe"
        || proc = "wowclassic64.exe"
        || proc = "wow.exe"
        || proc = "wow64.exe")
}


; Window helpers
; --------------
CenterWindowOnItsMonitor(hwnd) {
    CenterWindowOnMonitor(hwnd, GetMonitorIndexOfWindow(hwnd))
}

CenterWindowOnMonitor(hwnd, monIndex) {
    WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
    MonitorGetWorkArea(monIndex, &l, &t, &r, &b)
    WinMove(l + (r - l - w) / 2, t + (b - t - h) / 2, , , "ahk_id " hwnd)
}

GetMonitorIndexOfWindow(hwnd) {
    WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
    return GetMonitorIndexFromPoint(x + w/2, y + h/2)
}

GetMonitorIndexFromPoint(px, py) {
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        if (px >= l && px < r && py >= t && py < b)
            return A_Index
    }
    return 1
}