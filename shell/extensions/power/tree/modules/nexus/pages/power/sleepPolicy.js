.pragma library

// "Sleep after inactivity" is one entry of general.idle.timeouts, the list
// modules/IdleMonitors.qml turns into Quickshell IdleMonitors. These read and
// rewrite that entry and leave every other one (lock, display off, custom
// actions) exactly as it was. They only build lists; the page writes them.

// What IdleMonitors.handleIdleAction would do with an action, reduced to
// whether it suspends. A list runs through SessionManager.exec, which takes a
// bare verb or a two-word systemctl/loginctl command; a string other than
// lock/unlock is a Hyprland dispatch, and only an "exec" one runs a command.
// Hibernating or powering off is not "sleep" here and is left alone.
const sleepVerbs = ["suspend", "suspendthenhibernate", "hybridsleep"];

function commandSleeps(words) {
    if (!words.length)
        return false;
    const first = String(words[0]);
    const verb = (first === "systemctl" || first === "loginctl") ? words[1] : first;
    return sleepVerbs.includes(String(verb ?? "").replace(/[-_]/g, "").toLowerCase());
}

function isSleepAction(action) {
    if (Array.isArray(action))
        return commandSleeps(action);
    if (typeof action !== "string")
        return false;
    const words = action.trim().split(/\s+/);
    return words[0] === "exec" && commandSleeps(words.slice(1));
}

// A plain copy, so a list read from the config can be changed and written back.
function copy(timeouts) {
    return JSON.parse(JSON.stringify(timeouts ?? []));
}

// { state, index, seconds }:
//   "none"     no entry suspends: sleep is never automatic
//   "single"   exactly one does, at index; seconds is 0 when it is disabled
//   "multiple" more than one does: which one is meant is not clear, so
//              nothing here changes any of them
function classify(timeouts) {
    const list = copy(timeouts);
    const found = [];
    for (let i = 0; i < list.length; i++)
        if (isSleepAction(list[i]?.idleAction))
            found.push(i);
    if (found.length === 0)
        return { state: "none", index: -1, seconds: 0 };
    if (found.length > 1)
        return { state: "multiple", index: -1, seconds: 0 };
    const entry = list[found[0]];
    const on = (entry.enabled ?? true) !== false;
    return { state: "single", index: found[0], seconds: on ? Number(entry.timeout) || 0 : 0 };
}

// The list with sleep after `seconds` of inactivity, or null when it cannot
// be changed safely. With no sleep entry, one is added with upstream's own
// action; an existing one keeps its action and every other field.
function withSleepAfter(timeouts, seconds) {
    const c = classify(timeouts);
    if (c.state === "multiple" || !(seconds > 0))
        return null;
    const list = copy(timeouts);
    if (c.state === "none") {
        list.push({ timeout: seconds, idleAction: ["suspendThenHibernate"] });
        return list;
    }
    const entry = list[c.index];
    entry.timeout = seconds;
    if (entry.enabled === false)
        delete entry.enabled;
    return list;
}

// The list with automatic sleep off. The entry stays, disabled, so its action
// and fields come back with the next duration; lock and display off still run.
function withNever(timeouts) {
    const c = classify(timeouts);
    if (c.state === "multiple")
        return null;
    const list = copy(timeouts);
    if (c.state === "single")
        list[c.index].enabled = false;
    return list;
}

// The same entries with the same fields; the order of an entry's fields does
// not count, as shell.json keeps them sorted.
function canonical(value) {
    if (Array.isArray(value))
        return value.map(canonical);
    if (value && typeof value === "object") {
        const out = {};
        for (const key of Object.keys(value).sort())
            out[key] = canonical(value[key]);
        return out;
    }
    return value;
}

function same(a, b) {
    return JSON.stringify(canonical(copy(a))) === JSON.stringify(canonical(copy(b)));
}

