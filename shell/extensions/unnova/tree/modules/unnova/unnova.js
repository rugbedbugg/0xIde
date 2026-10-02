.pragma library

// UnNova's wording and formatting, kept apart from the UI so tests/run can
// check it without a shell.

function formatBytes(bytes) {
    const b = Math.max(0, Number(bytes) || 0);
    const units = ["B", "KiB", "MiB", "GiB", "TiB"];
    let v = b;
    let i = 0;
    while (v >= 1024 && i < units.length - 1) {
        v /= 1024;
        i++;
    }
    if (i === 0)
        return `${Math.round(v)} B`;
    return `${v >= 100 ? Math.round(v) : v.toFixed(1)} ${units[i]}`;
}

function formatPercent(value) {
    const v = Math.max(0, Number(value) || 0);
    return `${v < 10 ? v.toFixed(1) : Math.round(v)}%`;
}

function formatDuration(seconds) {
    let s = Math.max(0, Math.floor(Number(seconds) || 0));
    const d = Math.floor(s / 86400);
    s -= d * 86400;
    const h = Math.floor(s / 3600);
    s -= h * 3600;
    const m = Math.floor(s / 60);
    s -= m * 60;
    if (d > 0)
        return `${d} d ${h} h`;
    if (h > 0)
        return `${h} h ${m} min`;
    if (m > 0)
        return `${m} min ${s} s`;
    return `${s} s`;
}

const states = {
    "R": "Running",
    "S": "Sleeping",
    "D": "Waiting on I/O",
    "Z": "Zombie: exited, waiting for its parent",
    "T": "Paused",
    "t": "Stopped by a debugger",
    "I": "Idle",
    "X": "Dead",
    "P": "Parked"
};

function stateText(letter) {
    return states[letter] ?? (letter ? `Unknown (${letter})` : "Unknown");
}

// The actions offered by name. Each says what the signal asks of the process,
// not what UnNova hopes will happen.
const actions = [
    {
        id: "end",
        signal: "TERM",
        title: "End task",
        icon: "close",
        explanation: "Asks the process to exit normally. It can perform cleanup and save state before closing.",
        destructive: false
    },
    {
        id: "force",
        signal: "KILL",
        title: "Force stop",
        icon: "dangerous",
        explanation: "The process will stop immediately. It cannot perform normal cleanup or save state. Unsaved work may be lost.",
        destructive: true
    },
    {
        id: "pause",
        signal: "STOP",
        title: "Pause",
        icon: "pause",
        explanation: "Freezes the process until it is resumed. Its windows stop responding meanwhile, and nothing it was doing is lost.",
        destructive: false
    },
    {
        id: "resume",
        signal: "CONT",
        title: "Resume",
        icon: "play_arrow",
        explanation: "Lets a paused process carry on from where it stopped.",
        destructive: false
    },
    {
        id: "hangup",
        signal: "HUP",
        title: "Hang up",
        icon: "call_end",
        explanation: "Tells the process its terminal has gone away. Many programs exit; many services reload their configuration instead.",
        destructive: false
    },
    {
        id: "interrupt",
        signal: "INT",
        title: "Interrupt",
        icon: "front_hand",
        explanation: "The same as pressing Ctrl+C in its terminal. Most programs stop what they are doing and exit.",
        destructive: false
    }
];

function action(id) {
    return actions.find(a => a.id === id) ?? null;
}

// For a signal chosen from the full list.
function signalAction(name) {
    const known = actions.find(a => a.signal === name);
    if (known)
        return known;
    return {
        id: "signal",
        signal: name,
        title: `Send SIG${name}`,
        icon: "send",
        explanation: `Sends SIG${name}. What happens depends on the program: many exit, some ignore it, and some handle it in their own way.`,
        destructive: false
    };
}

function base(path) {
    const p = String(path ?? "").replace(/ \(deleted\)$/, "");
    return p.slice(p.lastIndexOf("/") + 1);
}

// What a process is, when that can be told reliably. A user can name a
// program anything, so a name alone is trusted only for processes owned by
// root, which a user cannot start; otherwise the executable's path decides.
const known = [
    {
        names: ["Hyprland"],
        text: "This is Hyprland, the compositor. Ending it closes every window and ends your session; unsaved work in any application may be lost."
    },
    {
        names: ["pipewire", "pipewire-pulse", "wireplumber"],
        text: "Part of the audio system (PipeWire). Ending it stops sound and microphone input until it is started again, which usually happens automatically."
    },
    {
        names: ["NetworkManager", "iwd", "wpa_supplicant", "systemd-networkd", "systemd-resolved"],
        text: "Part of networking. Ending it can drop your network connections until it is started again."
    },
    {
        names: ["dbus-daemon", "dbus-broker", "dbus-broker-launch"],
        text: "The message bus programs use to talk to each other. Ending it breaks most desktop services until you log in again."
    },
    {
        names: ["Xwayland"],
        text: "Runs X11 applications under Hyprland. Ending it closes every X11 window."
    },
    {
        names: ["sddm", "sddm-helper"],
        text: "The login manager. Ending it can end your session."
    },
    {
        names: ["systemd-logind"],
        text: "Tracks logins and sessions. Ending it can lock you out of the session until it restarts."
    }
];

// details: Processes.selected. shellPid: this shell's PID.
function context(details, shellPid) {
    if (!details || !details.pid)
        return "";
    if (details.pid === 1)
        return `This is the system's init process. Signalling it may affect the entire running system.`;
    if (details.kernelThread)
        return "A kernel thread: part of the kernel rather than a program. It ignores most signals.";
    if (details.pid === shellPid)
        return "This is the Caelestia shell, which is also running UnNova. Ending it closes the bar, panels, notifications and this window. Pausing it freezes them, and nothing here could resume it.";
    const exe = details.exeReadable ? base(details.exe) : "";
    const name = exe || (details.uid === 0 ? details.comm : "");
    if (!name)
        return "";
    if (name === "systemd")
        return details.uid === 0 ? "" : "Your user service manager. Ending it stops your user services and may end the session.";
    const entry = known.find(k => k.names.includes(name));
    return entry ? entry.text : "";
}

// Before acting on someone else's process: the kernel decides, but saying so
// first saves a surprise.
function ownership(details, ownUid) {
    if (!details || details.uid === undefined || details.uid === ownUid)
        return "";
    return details.uid === 0 ? "Owned by root. You most likely don't have permission to signal it." : `Owned by ${details.user}. You most likely don't have permission to signal it.`;
}

// The 0xIde tab. Each reads the service's own state; none starts anything.

// rt: { installing, operation, installed, serving, stopping, endpoint }, as
// AiRuntime has them.
function aiState(rt) {
    if (rt.installing)
        return rt.operation === "uninstall" ? "Removing" : "Installing";
    if (rt.installed === false)
        return "Not installed";
    if (!rt.serving)
        return "Stopped";
    if (rt.stopping)
        return "Stopping";
    return rt.endpoint ? "Ready" : "Starting";
}

// What can be done to the local AI right now, with the runtime's own calls.
function aiCan(rt) {
    return {
        start: rt.installed === true && !rt.serving && !rt.stopping && !rt.installing,
        unload: !!rt.serving && !rt.stopping && !rt.installing,
        restart: !!rt.endpoint && !!rt.serving && !rt.stopping && !rt.installing
    };
}

// dictate.sh records the listener's PID; a PID is only believed while it is
// running speech.py's listener.
function isListener(command) {
    return /(^|[\s\/])speech\.py listen(\s|$)/.test(String(command ?? ""));
}

function pidFromFile(text) {
    const t = String(text ?? "").trim();
    return /^[0-9]{1,10}$/.test(t) ? parseInt(t, 10) : 0;
}

function whisperModel(file) {
    const m = /^ggml-(.+)\.bin$/.exec(String(file ?? ""));
    return m ? `Whisper ${m[1]}` : String(file ?? "");
}

// sp: { working, operation, installed }, listening: bool.
function dictationState(sp, listening) {
    if (sp.working)
        return sp.operation === "remove" ? "Removing model" : "Installing model";
    if (listening)
        return "Listening";
    if (sp.installed === false)
        return "Model not installed";
    return sp.installed ? "Off" : "Checking";
}

// tr: { working, operation, language name, translating }.
function translationState(tr) {
    if (tr.working)
        return `${tr.operation === "remove" ? "Removing" : "Installing"} ${tr.languageName}`;
    return tr.translating ? "Translating" : "Idle";
}

function translationLanguages(names) {
    return names.length ? `Installed: ${names.join(", ")}, each to and from English` : "No languages installed";
}

function profileState(active) {
    return active?.name ?? "Unknown";
}
