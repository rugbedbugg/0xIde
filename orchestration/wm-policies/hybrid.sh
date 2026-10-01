# hybrid: windows tile, except the classes and tags the profile lists, which
# float. The lists are the profile's wm_float_classes and wm_float_tags,
# comma-separated plain names, matched exactly.

_hybrid_list() { dp_value "$DP_PROFILE" "$1" | tr ',' '\n' | tr -d ' ' | sed '/^$/d'; }

hybrid_describe() {
    echo "tile windows by default"
    echo "float windows of class: $(_hybrid_list wm_float_classes | paste -sd, | sed 's/,/, /g; s/^$/(none)/')"
    echo "float windows tagged: $(_hybrid_list wm_float_tags | paste -sd, | sed 's/,/, /g; s/^$/(none)/')"
}

hybrid_floats() {
    local class="$1" tags="$2" tag
    # "-" is how hypr_clients writes a window with no class.
    [ "$class" != - ] && _hybrid_list wm_float_classes | grep -qxF -- "$class" && return 0
    for tag in ${tags//,/ }; do
        # Hyprland marks tags a rule set dynamically with a trailing "*".
        _hybrid_list wm_float_tags | grep -qxF -- "${tag%\*}" && return 0
    done
    return 1
}

hybrid_rules() {
    _hybrid_list wm_float_classes | sed 's/^/float_class /'
    _hybrid_list wm_float_tags | sed 's/^/float_tag /'
}
