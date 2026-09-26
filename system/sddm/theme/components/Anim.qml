import QtQuick

// components/Anim.qml from the shell: one NumberAnimation per motion token,
// picked by type, with the same enum so ported code reads the same.
NumberAnimation {
    enum Type {
        StandardSmall = 0,
        Standard,
        StandardLarge,
        StandardExtraLarge,
        EmphasizedSmall,
        Emphasized,
        EmphasizedLarge,
        EmphasizedExtraLarge,
        FastSpatial,
        DefaultSpatial,
        SlowSpatial,
        FastEffects,
        DefaultEffects,
        SlowEffects
    }

    property int type: Anim.DefaultSpatial

    duration: {
        const d = Tokens.anim.durations;
        switch (type) {
        case Anim.FastSpatial:
            return d.expressiveFastSpatial;
        case Anim.DefaultSpatial:
            return d.expressiveDefaultSpatial;
        case Anim.SlowSpatial:
            return d.expressiveSlowSpatial;
        case Anim.FastEffects:
            return d.expressiveFastEffects;
        case Anim.DefaultEffects:
            return d.expressiveDefaultEffects;
        case Anim.SlowEffects:
            return d.expressiveSlowEffects;
        }
        return [d.small, d.normal, d.large, d.extraLarge][type % 4] ?? d.normal;
    }
    easing.type: Easing.BezierSpline
    easing.bezierCurve: {
        const a = Tokens.anim;
        switch (type) {
        case Anim.FastSpatial:
            return a.expressiveFastSpatial;
        case Anim.DefaultSpatial:
            return a.expressiveDefaultSpatial;
        case Anim.SlowSpatial:
            return a.expressiveSlowSpatial;
        case Anim.FastEffects:
            return a.expressiveFastEffects;
        case Anim.DefaultEffects:
            return a.expressiveDefaultEffects;
        case Anim.SlowEffects:
            return a.expressiveSlowEffects;
        }
        return type >= Anim.EmphasizedSmall && type <= Anim.EmphasizedExtraLarge ? a.emphasized : a.standard;
    }
}
