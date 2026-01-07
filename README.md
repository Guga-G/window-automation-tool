# Window Automation Tool (AutoHotkey v2)

I built this AutoHotkey v2 script for myself to improve my daily desktop life across multiple monitors.
It is practical and lightweight. Focused on fast window placement, multi-monitor support, predictable behavior in games and reliability under frequent use.
It's not a generic macro. It's state-aware, context-aware and designed to stay out of the way when it shouldn't interfere.


### Script

## DualMonitorMoveCenterWindow

Why I created it:
- Windows often opens dialogs and apps in weird positions
- Some apps ignore monitor boundaries
- I wanted an instant, consistent way to move and re-center anything without dragging windows around. I regularly switch between: games (windowed or borderless), browser, folders, development tools.

What it does:
This script lets me move and center windows across monitors using mouse buttons without touching the keyboard, breaking fullscreen apps or changing focus.

Mouse bindings:

**Mouse Button 5**
- Moves the window to the next monitor
- Centers it on that monitor
- Preserves window state

**Shift + Mouse Button 5**
- Centers the window on the current monitor

**Mouse Button 4**
- Restores down the window if needed and maximizes it

### Key features
- Works even when the window is not focused
- Does not interfere with games (World of Warcraft, CS2, VALORANT)
- Automatically elevates to admin level

Usage:
- Multi-monitor setups
- Laptop + external display working environment
- Fixing poorly positioned popups or tools

### Requirements
- Microsoft Windows 10/11
- AutoHotkey v2.x
- Multi-monitor setup recommended (but not required)

### Notes
This script was written for my personal comfort, but they are intentionally clean and reusable. Mouse buttons are read at the OS level.
