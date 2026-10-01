# stacking: every ordinary window floats and can be moved and resized freely,
# as on a stacking desktop. Existing windows float where they already are; new
# ones float as they open. Dialogs and anything Caelestia already floats keep
# its own treatment.

stacking_describe() {
    echo "float every tiled window where it already is"
    echo "float new windows as they open"
}

stacking_floats() { return 0; }

stacking_rules() { echo "float_all"; }
