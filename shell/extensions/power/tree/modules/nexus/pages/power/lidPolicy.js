.pragma library

// What closing the lid does, as the Power page shows and changes it. The
// values are logind's own; assets/power/logind_lid.py reads and writes them.

// In the order the menu offers them. Hibernate only where logind can.
const ACTIONS = ["suspend", "ignore", "lock", "hibernate"];

const LABELS = {
    suspend: "Suspend",
    ignore: "Do nothing",
    lock: "Lock screen",
    hibernate: "Hibernate",
    poweroff: "Power off",
    halt: "Halt",
    reboot: "Restart",
    kexec: "Restart into another kernel",
    "suspend-then-hibernate": "Suspend, then hibernate",
    "hybrid-sleep": "Hybrid sleep",
    sleep: "Sleep",
    "factory-reset": "Factory reset",
    "secure-attention-key": "Secure attention key"
};

const ICONS = {
    suspend: "bedtime",
    ignore: "do_not_disturb_on",
    lock: "lock",
    hibernate: "ac_unit"
};

function label(action) {
    return LABELS[action] ?? action;
}

function icon(action) {
    return ICONS[action] ?? "settings";
}

// The actions offered, given status.hibernate (logind's CanHibernate).
function offered(hibernate) {
    return ACTIONS.filter(a => a !== "hibernate" || hibernate === "yes");
}

// Whether value can be chosen from the menu as it is.
function choosable(value, hibernate) {
    return offered(hibernate).includes(value);
}

// Why the setting cannot be changed from the page, or "" when it can. status
// is logind_lid.py's answer, or null while there is none.
function blocked(status) {
    if (!status)
        return "reading";
    if (!status.ok)
        return "unreadable";
    if (!status.helper?.installed)
        return "missing";
    if (!status.helper.current)
        return "outdated";
    if (!status.helper.allowed)
        return "rule";
    if ((status.overriddenBy ?? []).length > 0)
        return "overridden";
    return "";
}

// What the two choices would be after picking one of them: logind_lid.py
// always sets both, so the other keeps what logind does now. An action the
// menu cannot offer (set by hand, say) falls back to logind's own default for
// that case, which the user sees in the menu before choosing.
function request(status, which, action) {
    const undocked = choosable(status.undocked, status.hibernate) ? status.undocked : "suspend";
    const docked = choosable(status.docked, status.hibernate) ? status.docked : "ignore";
    return which === "docked" ? [undocked, action] : [action, docked];
}

// On a charger logind uses HandleLidSwitchExternalPower, which is empty when
// unset and then follows HandleLidSwitch. A different value means something
// other than this page set it.
function chargerDiffers(status) {
    return !!status && !!status.externalPower && status.externalPower !== status.undocked;
}
