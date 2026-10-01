# tiling: Hyprland and Caelestia as they are. No window is floated by the
# policy; windows another policy floated are tiled again, and the rest keep
# whatever Hyprland and Caelestia's own rules gave them.

tiling_describe() {
    echo "tile windows another profile floated; leave the rest to Caelestia's own rules"
}

tiling_floats() { return 1; }
