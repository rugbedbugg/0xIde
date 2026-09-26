pragma Singleton

import QtQuick

// What Hyprland blurs behind the shell's translucent surfaces, for Frost to
// blur here: the wallpaper, filling the screen from its top left. Main sets
// both. mapToItem() is not a binding that updates by itself, so track is
// anything that moves the frosted items on screen; Frost re-reads its place
// whenever it changes.
QtObject {
    property Item source
    property real track
}
