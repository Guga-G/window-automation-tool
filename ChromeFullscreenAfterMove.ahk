#Requires AutoHotkey v2.0
#SingleInstance Force

if !A_IsAdmin {
    try Run '*RunAs "' A_ScriptFullPath '"'
    ExitApp
}
ProcessSetPriority("AboveNormal")

global DEBUG := true
global DEBUG_LOG := A_Temp "\ChromeFullscreenAfterMove_debug.log"

SetCapsLockState "AlwaysOff"

global GAME_EXES := Map(
    "wowclassic.exe", true,
    "wow.exe", true,
    "cs2.exe", true,
    "valorant-win64-shipping.exe", true
)

global RESTORE_START_DELAY_MS_TWITCH := 180
global RESTORE_START_DELAY_MS_YOUTUBE := 160

global POLL_INTERVAL_MS := 25
global POLL_MAX_WAIT_MS := 2000

; ✅ micro-tune
global STABLE_TICKS_TWITCH := 2
global STABLE_TICKS_YOUTUBE := 2

global RESTORE_TRIES_TWITCH := 8
global RESTORE_TRIES_YOUTUBE := 5

global RESTORE_RETRY_SLEEP_MS_TWITCH := 130
global RESTORE_RETRY_SLEEP_MS_YOUTUBE := 95

global POST_ACTIVATE_MS := 90
global ONLY_YT_TWITCH := true

global g_restoreToken := 0

global g_polling := false
global g_pollToken := 0
global g_pollStartTick := 0
global g_pollMinDelay := 0
global g_pollLabel := ""
global g_pollSite := ""

global g_lastSig := ""
global g_stableCount := 0

*CapsLock::HandleCapsHotkey(false)
*+CapsLock::HandleCapsHotkey(true)

HandleCapsHotkey(isShift) {
    SetCapsLockState "AlwaysOff"

    hwnd := WinExist("A")
    exe := hwnd ? SafeGetExe(hwnd) : ""

    if (hwnd && IsGameExe(exe)) {
        SendInput "{Blind}{vk14sc03A}"
        SetCapsLockState "AlwaysOff"
        return
    }

    if (!hwnd || exe != "chrome.exe") {
        if DEBUG
            Dbg("Caps passthrough: exe=" exe)
        SendInput "{Blind}{vk14sc03A}"
        SetCapsLockState "AlwaysOff"
        return
    }

    if isShift
        MoveAndMaybeRestoreFullscreen("^+2", "Shift+CapsLock -> ^+2")
    else
        MoveAndMaybeRestoreFullscreen("^+1", "CapsLock -> ^+1")

    SetCapsLockState "AlwaysOff"
}

IsGameExe(exe) {
    global GAME_EXES
    return GAME_EXES.Has(StrLower(exe))
}

MoveAndMaybeRestoreFullscreen(moveHotkey, label) {
    global ONLY_YT_TWITCH, g_restoreToken

    hwnd := WinExist("A")
    if !hwnd {
        Dbg(label ": no active window")
        return
    }

    exe := SafeGetExe(hwnd)
    title := SafeGetTitle(hwnd)

    if (exe != "chrome.exe") {
        Dbg(label ": active exe=" exe " -> send only")
        SendInput moveHotkey
        return
    }

    wasFull := IsChromeFullscreenLike(hwnd)
    site := DetectSiteFromTitle(title)

    Dbg(label ": before move | wasFull=" (wasFull?1:0) " | site=" site " | title=[" title "]")

    if (ONLY_YT_TWITCH && site = "other") {
        SendInput moveHotkey
        return
    }

    SendInput moveHotkey

    if wasFull {
        g_restoreToken += 1
        myToken := g_restoreToken
        ArmPollingRestore(label, site, myToken)
    }
}

ArmPollingRestore(label, site, token) {
    global g_polling, g_pollToken, g_pollStartTick, g_pollMinDelay, g_pollLabel, g_pollSite
    global POLL_INTERVAL_MS, g_lastSig, g_stableCount
    global RESTORE_START_DELAY_MS_TWITCH, RESTORE_START_DELAY_MS_YOUTUBE

    if (g_polling) {
        SetTimer(PollRestore, 0)
        g_polling := false
    }

    g_pollToken := token
    g_pollStartTick := A_TickCount
    g_pollLabel := label
    g_pollSite := site

    g_lastSig := ""
    g_stableCount := 0

    if (site = "youtube")
        g_pollMinDelay := RESTORE_START_DELAY_MS_YOUTUBE
    else
        g_pollMinDelay := RESTORE_START_DELAY_MS_TWITCH

    g_polling := true
    Dbg(label ": polling restore armed (minDelay=" g_pollMinDelay "ms, interval=" POLL_INTERVAL_MS "ms, token=" token ")")
    SetTimer(PollRestore, POLL_INTERVAL_MS)
}

PollRestore() {
    global g_polling, g_pollToken, g_pollStartTick, g_pollMinDelay, g_pollLabel, g_pollSite
    global g_restoreToken, POLL_MAX_WAIT_MS
    global g_lastSig, g_stableCount
    global STABLE_TICKS_TWITCH, STABLE_TICKS_YOUTUBE

    if (!g_polling) {
        SetTimer(PollRestore, 0)
        return
    }

    if (g_pollToken != g_restoreToken) {
        Dbg(g_pollLabel ": polling: token mismatch -> stop (token=" g_pollToken " current=" g_restoreToken ")")
        g_polling := false
        SetTimer(PollRestore, 0)
        return
    }

    elapsed := A_TickCount - g_pollStartTick
    if (elapsed > POLL_MAX_WAIT_MS) {
        Dbg(g_pollLabel ": polling: max wait exceeded (" elapsed "ms) -> stop")
        g_polling := false
        SetTimer(PollRestore, 0)
        return
    }

    if (elapsed < g_pollMinDelay)
        return

    hwnd := WinExist("A")
    if (!hwnd)
        return
    if (SafeGetExe(hwnd) != "chrome.exe")
        return

    sig := GetWindowSig(hwnd)
    if (sig = "") {
        g_lastSig := ""
        g_stableCount := 0
        return
    }

    if (sig = g_lastSig)
        g_stableCount += 1
    else {
        g_lastSig := sig
        g_stableCount := 1
    }

    needStable := (g_pollSite = "youtube") ? STABLE_TICKS_YOUTUBE : STABLE_TICKS_TWITCH
    if (g_stableCount < needStable)
        return

    Dbg(g_pollLabel ": polling: ready after " elapsed "ms (stable=" g_stableCount ") -> start restore")

    g_polling := false
    SetTimer(PollRestore, 0)

    RestoreFullscreenWithRetries(g_pollLabel, g_pollSite, g_pollToken)
}

GetWindowSig(hwnd) {
    try {
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        return x "," y "," w "," h
    } catch {
        return ""
    }
}

RestoreFullscreenWithRetries(label, site, token) {
    global g_restoreToken, POST_ACTIVATE_MS
    global RESTORE_TRIES_TWITCH, RESTORE_TRIES_YOUTUBE
    global RESTORE_RETRY_SLEEP_MS_TWITCH, RESTORE_RETRY_SLEEP_MS_YOUTUBE

    if (token != g_restoreToken) {
        Dbg(label ": RestoreFS: token mismatch -> abort (token=" token " current=" g_restoreToken ")")
        return
    }

    hwnd := WinExist("A")
    if !hwnd {
        Dbg(label ": RestoreFS: no active window")
        return
    }
    if (SafeGetExe(hwnd) != "chrome.exe") {
        Dbg(label ": RestoreFS: active exe != chrome -> abort")
        return
    }

    if !SafeActivate(hwnd, 900) {
        Dbg(label ": RestoreFS: activate failed -> abort")
        return
    }
    Sleep POST_ACTIVATE_MS

    if IsChromeFullscreenLike(hwnd) {
        Dbg(label ": RestoreFS: already fullscreen -> done")
        return
    }

    tries := (site = "youtube") ? RESTORE_TRIES_YOUTUBE : RESTORE_TRIES_TWITCH
    retrySleep := (site = "youtube") ? RESTORE_RETRY_SLEEP_MS_YOUTUBE : RESTORE_RETRY_SLEEP_MS_TWITCH

    Dbg(label ": RestoreFS: begin retries tries=" tries)

    ClearMods()
    if TryControlSendKeys(hwnd, "f") {
        Sleep 70
        if IsChromeFullscreenLike(hwnd) {
            Dbg(label ": RestoreFS: fullscreen restored -> done (early shot via ControlSend)")
            return
        }
    }

    Loop tries {
        if (token != g_restoreToken) {
            Dbg(label ": RestoreFS: token changed mid-loop -> abort")
            return
        }

        if !SafeActivate(hwnd, 700) {
            Dbg(label ": RestoreFS: activate failed in loop -> abort")
            return
        }
        Sleep POST_ACTIVATE_MS

        if IsChromeFullscreenLike(hwnd) {
            Dbg(label ": RestoreFS: fullscreen detected -> done (attempt " A_Index ")")
            return
        }

        ClearMods()
        TryControlSendKeys(hwnd, "{Esc}")
        Sleep 40
        TryControlSendKeys(hwnd, "f")

        Sleep retrySleep

        if IsChromeFullscreenLike(hwnd) {
            Dbg(label ": RestoreFS: fullscreen restored -> done (attempt " A_Index " via ControlSend)")
            return
        } else {
            Dbg(label ": RestoreFS: not fullscreen yet (attempt " A_Index ")")
        }
    }

    Dbg(label ": RestoreFS: gave up after " tries " tries")
}

DetectSiteFromTitle(title) {
    t := StrLower(title)
    if InStr(t, "youtube")
        return "youtube"
    if InStr(t, "twitch")
        return "twitch"
    return "other"
}

IsChromeFullscreenLike(hwnd) {
    try WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
    catch {
        return false
    }

    cx := x + (w/2)
    cy := y + (h/2)
    mon := GetMonitorIndexFromPoint(cx, cy)
    MonitorGet(mon, &ml, &mt, &mr, &mb)

    tol := 3
    return (Abs(x - ml) <= tol
        && Abs(y - mt) <= tol
        && Abs((x + w) - mr) <= tol
        && Abs((y + h) - mb) <= tol)
}

GetMonitorIndexFromPoint(px, py) {
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        if (px >= l && px < r && py >= t && py < b)
            return A_Index
    }
    return 1
}

SafeGetExe(hwnd) {
    exe := ""
    try exe := StrLower(WinGetProcessName("ahk_id " hwnd))
    return exe
}

SafeGetTitle(hwnd) {
    title := ""
    try title := WinGetTitle("ahk_id " hwnd)
    return title
}

SafeActivate(hwnd, timeoutMs := 900) {
    try WinActivate("ahk_id " hwnd)
    catch {
        return false
    }

    start := A_TickCount
    while (A_TickCount - start < timeoutMs) {
        Sleep 25
        if (WinExist("A") = hwnd)
            return true
    }
    return false
}

ClearMods() {
    SendInput "{Shift up}{Ctrl up}{Alt up}{LWin up}{RWin up}"
}

TryControlSendKeys(hwnd, keys) {
    try {
        ControlSend(keys, , "ahk_id " hwnd)
        return true
    } catch {
        return false
    }
}

Dbg(msg) {
    global DEBUG, DEBUG_LOG
    if !DEBUG
        return
    ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    try FileAppend(ts " | " msg "`n", DEBUG_LOG, "UTF-8")
}
