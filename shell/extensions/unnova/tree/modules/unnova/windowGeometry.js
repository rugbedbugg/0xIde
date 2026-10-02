.pragma library

// Leave a little breathing room even when the display is smaller than our
// useful minimum. The compositor retains control of floating placement.
function dimension(usable, fraction, preferred, minimum, maximum) {
    const limit = Math.max(1, Math.floor(usable - 40));
    const low = Math.min(minimum, limit);
    const high = Math.min(maximum, limit);
    return {
        minimum: low,
        preferred: Math.round(Math.max(low, Math.min(preferred, usable * fraction, high))),
        maximum: high
    };
}

function sizing(width, height, reserved) {
    // Hyprland reports left, top, right, bottom reservations.
    const edges = [0, 1, 2, 3].map(i => Math.max(0, Number(reserved[i]) || 0));
    return {
        width: dimension(width - edges[0] - edges[2], 0.78, 1320, 960, 1440),
        height: dimension(height - edges[1] - edges[3], 0.82, 790, 600, 900)
    };
}
