#Requires AutoHotkey v2.0
#SingleInstance Force


; <System setup>

if !A_IsAdmin {
    try {
        Run '*RunAs "' A_ScriptFullPath '"'
    }
    ExitApp
}

ProcessSetPriority("AboveNormal")

; Track windows I just exited fullscreen on (Mouse4 logic)
global FullscreenJustExited := Map()

; =========================
; Hotkeys (mouse)
; NOTE: wildcard * forces hook-style handling without v1 directives
; =========================
*XButton1::HandleMouse4()
*XButton2::HandleMouse5(true)
*+XButton2::HandleMouse5(false)


; <Mouse handlers>

HandleMouse4() {
    prevActive := WinExist("A")

    ; Determine hovered top level window (works even if inactive)
    hwnd := GetHoveredTopLevelWindowOrActive()
    if !hwnd
        return

    ; Game safety: if hovered is a game or active is a game -> pass through
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

    ; Game safety: if hovered is a game or active is a game -> pass through
    if IsGameWindowHwnd(hwnd) || IsGameWindowHwnd(prevActive) {
        Send "{Blind}{XButton2}"
        return
    }

    ; Shift+Mouse5 -> center on same monitor
    if !isMove {
        CenterWindowOnItsMonitor(hwnd)
        return
    }

    ; Mouse5 -> move to next monitor + center (NO ACTIVATE)
    cur := GetMonitorIndexOfWindow(hwnd)
    count := MonitorGetCount()
    if (count < 2)
        return

    target := (cur = count) ? 1 : (cur + 1)
    CenterWindowOnMonitor(hwnd, target)

    ; Keep focus on whatever was active before
    if (prevActive && WinExist("A") != prevActive) {
        try {
            WinActivate("ahk_id " prevActive)
        } catch as e {
            ; ignore
        }
    }
}


; <Hovered window getter (top level) with shell filtering>

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
    } catch as e {
        cls := ""
    }

    ; Ignore desktop/taskbar shells -> fallback to active
    if (cls = "Shell_TrayWnd" || cls = "WorkerW" || cls = "Progman")
        return WinExist("A")

    return hwnd
}

GetTopLevelHwnd(hwnd) {
    ; GA_ROOT = 2 (top-level ancestor)
    try {
        return DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr")
    } catch as e {
        return 0
    }
}


; <Mouse4: fullscreen-aware restore/maximize without focus stealing>

ToggleRestoreMaximize_NoFocus_WithFullscreen(hwnd, prevActive) {
    global FullscreenJustExited

    if IsTrueFullscreenWindow(hwnd) {
        ; Must temporarily activate to reliably send F11/Esc (Chrome style)
        try {
            WinActivate("ahk_id " hwnd)
        } catch as e {
            return
        }
        Sleep 40
        Send "{F11}"
        Sleep 80
        Send "{Esc}"
        Sleep 80

        try WinRestore("ahk_id " hwnd)

        FullscreenJustExited[hwnd] := true

        if (prevActive && WinExist("A") != prevActive) {
            try WinActivate("ahk_id " prevActive)
            catch as e {
            }
        }
        return
    }

    if FullscreenJustExited.Has(hwnd) {
        mm := WinGetMinMax("ahk_id " hwnd)
        if (mm = -1)
            WinRestore("ahk_id " hwnd)

        mm2 := WinGetMinMax("ahk_id " hwnd)
        if (mm2 != 1)
            WinMaximize("ahk_id " hwnd)

        FullscreenJustExited.Delete(hwnd)

        if (prevActive && WinExist("A") != prevActive) {
            try WinActivate("ahk_id " prevActive)
            catch as e {
            }
        }
        return
    }

    mm := WinGetMinMax("ahk_id " hwnd)
    if (mm = -1) {
        WinRestore("ahk_id " hwnd)
        mm := 0
    }

    if (mm = 1)
        WinRestore("ahk_id " hwnd)
    else
        WinMaximize("ahk_id " hwnd)

    if (prevActive && WinExist("A") != prevActive) {
        try WinActivate("ahk_id " prevActive)
        catch as e {
        }
    }
}

IsTrueFullscreenWindow(hwnd) {
    try {
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
    } catch as e {
        return false
    }

    mm := WinGetMinMax("ahk_id " hwnd)
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


; <Game detection>

IsGameWindowHwnd(hwnd) {
    if !hwnd
        return false

    proc := ""
    try {
        proc := StrLower(WinGetProcessName("ahk_id " hwnd))
    } catch as e {
        return false
    }

    return (proc = "cs2.exe"
        || proc = "valorant-win64-shipping.exe"
        || proc = "wowclassic.exe"
        || proc = "wowclassic64.exe"
        || proc = "wow.exe"
        || proc = "wow64.exe")
}


; <Window/monitor helpers>

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
