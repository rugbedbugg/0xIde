import QtQuick

// Material Symbols Rounded, with the fill and grade axes the shell sets.
StyledText {
    property real fill
    property int grade: Colours.light ? 0 : -25
    property int size: Tokens.font.iconSmall

    font.family: Tokens.font.icon
    font.pointSize: Math.max(1, size)
    font.variableAxes: ({ "FILL": fill, "GRAD": grade })
}
