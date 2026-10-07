// UnNova's process core, driven directly: a made-up /proc for parsing and
// views, and disposable children of this program for signals. Nothing outside
// this program's own children is ever signalled.
//
// Prints "ok <what>" or "FAIL <what>" per check; tests/run counts them.

#include "../shell/plugin/src/procfs.hpp"

#include <cerrno>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <filesystem>
#include <string>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

using namespace caelestia::procfs;

namespace {

int failures = 0;

void check(bool cond, const std::string& what) {
    std::printf("%s %s\n", cond ? "ok" : "FAIL", what.c_str());
    if (!cond) {
        ++failures;
    }
}

std::string root;

void put(const std::string& rel, const std::string& data) {
    const std::string path = root + "/" + rel;
    const auto slash = path.rfind('/');
    std::string dir = path.substr(0, slash);
    for (std::size_t i = root.size() + 1; i <= dir.size(); ++i) {
        if (i == dir.size() || dir[i] == '/') {
            ::mkdir(dir.substr(0, i).c_str(), 0755);
        }
    }
    std::ofstream(path, std::ios::binary) << data;
}

std::string statLine(int pid, const std::string& comm, char state, int ppid, unsigned long long start,
    unsigned long long utime = 0, unsigned long long flags = 0, long threads = 1) {
    return std::to_string(pid) + " (" + comm + ") " + state + " " + std::to_string(ppid) + " 0 0 0 -1 " +
           std::to_string(flags) + " 0 0 0 0 " + std::to_string(utime) + " 0 0 0 20 0 " + std::to_string(threads) +
           " 0 " + std::to_string(start) + " 0 0 0 0 0\n";
}

void process(int pid, const std::string& comm, int ppid, unsigned long long start, const std::string& cmdline,
    unsigned long long residentPages = 100, unsigned long long flags = 0) {
    const std::string d = std::to_string(pid);
    put(d + "/stat", statLine(pid, comm, 'S', ppid, start, 0, flags));
    put(d + "/statm", "1000 " + std::to_string(residentPages) + " 10 1 0 1 0\n");
    put(d + "/cmdline", cmdline);
}

pid_t child() {
    const pid_t pid = ::fork();
    if (pid == 0) {
        for (;;) {
            ::pause();
        }
    }
    return pid;
}

bool running(pid_t pid) {
    int status = 0;
    return ::waitpid(pid, &status, WNOHANG) == 0;
}

void reap(pid_t pid) {
    ::kill(pid, SIGKILL);
    ::waitpid(pid, nullptr, 0);
}

int termSignal(pid_t pid) {
    int status = 0;
    ::waitpid(pid, &status, 0);
    return WIFSIGNALED(status) ? WTERMSIG(status) : 0;
}

Entry entry(int pid, int ppid, const std::string& name, std::uint64_t memory, double cpu = 0,
    const std::string& user = "me", const std::string& command = "") {
    Entry e;
    e.id = {pid, static_cast<std::uint64_t>(pid) * 10};
    e.ppid = ppid;
    e.name = name;
    e.user = user;
    e.command = command.empty() ? "/usr/bin/" + name : command;
    e.memory = memory;
    e.cpu = cpu;
    e.cpuSort = cpu;
    return e;
}

std::string names(const std::vector<Entry>& entries, const std::vector<Row>& rows, bool depth = false) {
    std::string out;
    for (const auto& r : rows) {
        if (!out.empty()) {
            out += ",";
        }
        if (depth) {
            out += std::to_string(r.depth);
        }
        out += entries[r.entry].name;
    }
    return out;
}

int denyingSender(int, pid_t, int) {
    return EPERM;
}

int goneSender(int, pid_t, int) {
    return ESRCH;
}

int sends = 0;
int countingSender(int, pid_t, int) {
    ++sends;
    return 0;
}

} // namespace

int main() {
    char tmpl[] = "/tmp/unnova-procfs-XXXXXX";
    if (!::mkdtemp(tmpl)) {
        std::perror("mkdtemp");
        return 2;
    }
    root = tmpl;
    const Reader fake(root);
    const Reader real("/proc");
    const std::string fakeMarker = root + "/executed";

    // Parsing
    {
        auto s = parseStat("1234 (a) b (c) R 77 0 0 0 -1 4194560 0 0 0 0 5 6 0 0 20 0 3 0 999 0\n");
        check(s && s->comm == "a) b (c" && s->state == 'R' && s->ppid == 77 && s->utime == 5 && s->stime == 6 &&
                  s->threads == 3 && s->startTime == 999,
            "a name holding spaces and parentheses is read up to the last parenthesis");
        s = parseStat("42 (evil) R 1 2 3) S 9 0 0 0 -1 0 0 0 0 0 1 1 0 0 20 0 1 0 555 0\n");
        check(s && s->comm == "evil) R 1 2 3" && s->ppid == 9 && s->startTime == 555,
            "a name that imitates the fields after it cannot change them");
        check(!parseStat(""), "an empty stat is refused");
        check(!parseStat("garbage"), "a stat without a name is refused");
        check(!parseStat("12 (x) S 1 0 0\n"), "a stat with missing fields is refused");
        check(!parseStat("12 (x) S -5 0 0 0 -1 0 0 0 0 0 1 1 0 0 20 0 1 0 5 0\n"), "a negative parent is refused");
        check(!parseStat("x12 (x) S 1 0 0 0 -1 0 0 0 0 0 1 1 0 0 20 0 1 0 5 0\n"), "a PID that is not a number is refused");
        check(!parseStat("12 (x) S 1 0 0 0 -1 0 0 0 0 0 1 1 0 0 20 0 1 0 5x 0\n"), "a start time that is not a number is refused");
    }

    // Keys
    {
        const auto k = parseKey("1234:5678");
        check(k && k->pid == 1234 && k->startTime == 5678 && formatKey(*k) == "1234:5678", "a key round-trips");
        bool allRefused = true;
        for (const char* bad : {"", "1234", "1234:", ":5", "-1:5", "0:5", "12:5x", "1 2:3", "12:5:6", "+12:5", "12:-5",
                 "99999999999999999999:1", "abc:def"}) {
            if (parseKey(bad)) {
                allRefused = false;
                std::printf("  accepted malformed key %s\n", bad);
            }
        }
        check(allRefused, "malformed identities are refused");
    }

    // Enumeration over a made-up /proc
    {
        process(1, "systemd", 0, 10, std::string("/sbin/init\0splash\0", 18));
        process(2, "kthreadd", 0, 11, "", 0, 0x00200000);
        process(100, "Hyprland", 1, 500, std::string("Hyprland\0", 9), 5000);
        process(101, "Isolated Web Co", 100, 600, std::string("/usr/lib/firefox/firefox\0-contentproc\0", 39), 40000);
        // Unicode in names and arguments, as the kernel stores them: bytes.
        process(102, "naïve-日本", 100, 610, std::string("/opt/naïve-日本\0--flag=ünï\0", 32));
        // Directories that are not processes, or processes that vanished.
        ::mkdir((root + "/self").c_str(), 0755);
        ::mkdir((root + "/200").c_str(), 0755);
        put("201/stat", "this is not a stat line");
        put("202/stat", statLine(203, "liar", 'S', 1, 5)); // says it is another PID
        put("meminfo", "MemTotal:       16000000 kB\nMemFree: 1 kB\nMemAvailable:    8000000 kB\nSwapTotal:       4000000 kB\nSwapFree:        3000000 kB\n");
        put("stat", "cpu  1 2 3\nbtime 1700000000\nprocesses 5\n");

        const auto all = fake.scan();
        std::string pids;
        for (const auto& s : all) {
            pids += std::to_string(s.id.pid) + ",";
        }
        check(all.size() == 5, "every readable process is found, and nothing else (" + pids + ")");
        const auto s101 = fake.sample(101);
        check(s101 && s101->ppid == 100 && s101->id.startTime == 600, "a process's parent and start time are read");
        check(s101 && s101->residentBytes == 40000 * static_cast<std::uint64_t>(::sysconf(_SC_PAGESIZE)),
            "resident memory comes from statm pages");
        check(!fake.sample(200), "a process that vanished mid-scan is skipped");
        check(!fake.sample(201), "malformed stat data is skipped");
        check(!fake.sample(202), "a stat naming a different PID is skipped");
        const auto k2 = fake.sample(2);
        check(k2 && k2->kernelThread, "a kernel thread is recognised by its flag");
        const auto a2 = fake.arguments(2);
        check(a2 && a2->empty() && displayName("kthreadd", *a2) == "kthreadd", "an empty command line is read as no arguments");
        const auto a101 = fake.arguments(101);
        check(a101 && displayName("Isolated Web Co", *a101) == "Isolated Web Co",
            "a short name that is not the program's own is kept");
        check(displayName("firefox-bin-lon", {"/usr/lib/firefox/firefox-bin-long-name"}) == "firefox-bin-long-name",
            "a name the kernel cut at 15 bytes is completed from the program's path");
        const auto a102 = fake.arguments(102);
        check(a102 && a102->size() == 2 && (*a102)[0] == "/opt/naïve-日本" && (*a102)[1] == "--flag=ünï",
            "Unicode arguments are read byte for byte");
        check(!fake.arguments(999), "a missing process has no arguments");
        put("102/cmdline", std::string("program\0\0middle\0\0", 17));
        const auto emptyArgs = fake.arguments(102);
        check(emptyArgs && *emptyArgs == std::vector<std::string>{"program", "", "middle", ""},
            "empty arguments including the last argument are preserved");
        put("102/statm", "malformed");
        check(fake.sample(102) && fake.sample(102)->residentBytes == 0,
            "unavailable memory fields do not prevent enumeration");
        put("102/stat", statLine(102, "quotes'\"`$();\n日本", 'S', 100, 610));
        check(fake.sample(102) && fake.sample(102)->comm == "quotes'\"`$();\n日本",
            "hostile names and embedded newlines remain data");
        check(!fake.executable(101), "an executable that cannot be read is reported as unknown");
        const auto mem = fake.memInfo();
        check(mem && mem->total == 16000000ULL * 1024 && mem->swapTotal == 4000000ULL * 1024 && mem->swapFree == 3000000ULL * 1024,
            "memory and swap come from meminfo");
        check(fake.bootTime() == 1700000000ULL, "the boot time comes from /proc/stat");

        // A command line far longer than anything shown.
        process(300, "long", 1, 700, std::string(200000, 'a'));
        const auto a300 = fake.arguments(300);
        check(a300 && a300->size() == 1 && (*a300)[0].size() <= 64 * 1024, "a very long command line is cut, not fatal");

        // Unreadable stat, where permissions can be enforced at all.
        process(301, "secret", 1, 800, "x");
        ::chmod((root + "/301/stat").c_str(), 0);
        if (::access((root + "/301/stat").c_str(), R_OK) != 0) {
            check(!fake.sample(301), "a process whose stat cannot be read is skipped");
        } else {
            std::printf("ok an unreadable stat cannot be tested as root\n");
        }

        // The real /proc: fields root keeps to itself do not fail the scan.
        const auto mine = real.scan();
        bool hasSelf = false;
        for (const auto& s : mine) {
            hasSelf = hasSelf || s.id.pid == ::getpid();
        }
        check(mine.size() > 1 && hasSelf, "the real /proc lists this process among others");
        // PID 1 can be our own process in a container; readability is kernel policy.
        check(!fake.executable(999), "an inaccessible or missing executable is reported as unknown");
    }

    // Signals, against this program's own children only
    {
        const pid_t a = child();
        const pid_t b = child();
        ::usleep(20000);
        const auto sa = real.startTime(a);
        const auto sb = real.startTime(b);
        check(sa && sb, "children have start times");

        // PID reuse: the same PID with a different start time is another process.
        check(sendSignal(real, {a, *sa + 1}, "KILL") == SignalResult::Stale, "a PID whose start time differs is refused as stale");
        check(running(a), "the process holding that PID was not signalled");
        sendSignal(real, {a, *sa + 1}, "KILL", countingSender);
        sendSignal(real, {0, 0}, "TERM", countingSender);
        sendSignal(real, {a, *sa}, "invalid", countingSender);
        put(std::to_string(a) + "/stat", "malformed");
        sendSignal(fake, {a, *sa}, "KILL", countingSender);
        put(std::to_string(a) + "/stat", statLine(a + 1, "wrong PID", 'S', 1, *sa));
        sendSignal(fake, {a, *sa}, "KILL", countingSender);
        check(sends == 0 && running(a), "failed identity, PID and signal validation never calls the sender");

        check(sendSignal(real, {a, *sa}, "FOO") == SignalResult::InvalidSignal, "an unknown signal is refused");
        check(sendSignal(real, {a, *sa}, "") == SignalResult::InvalidSignal, "an empty signal is refused");
        check(sendSignal(real, {a, *sa}, "9") == SignalResult::InvalidSignal, "a signal number instead of a name is refused");
        check(sendSignal(real, {a, *sa}, "TERM; kill -9 -1") == SignalResult::InvalidSignal, "a signal with anything appended is refused");
        check(sendSignal(real, {a, *sa}, "sigterm") == SignalResult::InvalidSignal, "signal names are exact");
        check(running(a), "nothing was sent after a refusal");

        check(sendSignal(real, {0, 0}, "TERM") == SignalResult::InvalidIdentity, "PID 0, the caller's process group, is refused");
        check(sendSignal(real, {-1, 0}, "TERM") == SignalResult::InvalidIdentity, "PID -1, every process, is refused");
        check(running(a) && running(b), "refused identities reached nobody");

        check(sendSignal(real, {a, *sa}, "STOP") == SignalResult::Sent, "SIGSTOP is sent");
        int status = 0;
        check(::waitpid(a, &status, WUNTRACED) == a && WIFSTOPPED(status), "the process stopped");
        check(sendSignal(real, {a, *sa}, "SIGCONT") == SignalResult::Sent, "SIGCONT is sent");
        check(::waitpid(a, &status, WCONTINUED) == a && WIFCONTINUED(status), "the process resumed");

        check(sendSignal(real, {a, *sa}, "TERM") == SignalResult::Sent, "SIGTERM is sent");
        check(termSignal(a) == SIGTERM, "SIGTERM reached exactly the intended process");
        check(running(b), "its sibling was untouched");

        check(sendSignal(real, {b, *sb}, "KILL") == SignalResult::Sent, "SIGKILL is sent");
        check(termSignal(b) == SIGKILL, "SIGKILL reached exactly the intended process");

        // Gone before the action: reaped, so nothing has that PID any more.
        check(sendSignal(real, {a, *sa}, "TERM") == SignalResult::Exited, "a process that already exited is reported as exited");
        check(!alive(real, {a, *sa}), "an exited process is not alive");

        const pid_t c = child();
        ::usleep(20000);
        const auto sc = real.startTime(c);
        check(alive(real, {c, *sc}) && !alive(real, {c, *sc + 1}), "alive checks the start time, not just the PID");
        check(sendSignal(real, {c, *sc}, "TERM", denyingSender) == SignalResult::PermissionDenied,
            "a refusal from the kernel is reported as missing permission");
        check(sendSignal(real, {c, *sc}, "TERM", goneSender) == SignalResult::Exited, "a process gone at the last moment is reported as exited");
        check(running(c), "neither reached the process");
        reap(c);

        // Hostile arguments stay data.
        const std::string hostile = std::string("a'b\"c`touch ") + fakeMarker + "`$(touch " + fakeMarker + ");touch " + fakeMarker +
                                    "\nnaïve 日本 " + std::string(5000, 'x');
        const pid_t h = ::fork();
        if (h == 0) {
            char* const argv[] = {const_cast<char*>(hostile.c_str()), const_cast<char*>("30"), nullptr};
            ::execv("/usr/bin/sleep", argv);
            ::_exit(127);
        }
        ::usleep(100000);
        const auto ah = real.arguments(h);
        check(ah && !ah->empty() && (*ah)[0] == hostile, "hostile arguments are read back exactly");
        Entry he = entry(h, 1, displayName("sleep", ah ? *ah : std::vector<std::string>{}), 1, 0, "me", ah ? joinArguments(*ah) : "");
        check(matches(he, lowered("$(touch")) && matches(he, "日本"), "hostile text is searchable as text");
        const auto sh = real.startTime(h);
        check(sh && sendSignal(real, {h, *sh}, "TERM") == SignalResult::Sent && termSignal(h) == SIGTERM, "a process with hostile arguments is signalled by identity");
        check(::access(fakeMarker.c_str(), F_OK) != 0, "nothing in the arguments was executed");

        for (const auto& spec : std::vector<SignalSpec>{{SIGHUP, "HUP"}, {SIGINT, "INT"}}) {
            const pid_t p = child();
            const auto start = real.startTime(p);
            check(start && sendSignal(real, {p, *start}, spec.name) == SignalResult::Sent && termSignal(p) == spec.number,
                "SIG" + std::string(spec.name) + " reaches only its disposable child");
        }
    }

    // Real processes can exit between directory enumeration and individual reads.
    {
        bool valid = true;
        for (int i = 0; i < 100; ++i) {
            const pid_t p = ::fork();
            if (p == 0) {
                ::_exit(0);
            }
            if (p < 0) {
                valid = false;
                break;
            }
            for (const auto& sample : real.scan()) {
                valid = valid && sample.id.pid > 0 && sample.ppid >= 0;
            }
            ::waitpid(p, nullptr, 0);
            valid = valid && !real.sample(p);
        }
        check(valid, "100 rapid process creations and exits leave no malformed or stale samples");
    }

    // Views
    {
        std::vector<Entry> e = {
            entry(1, 0, "systemd", 10 << 20, 0.0, "root"),
            entry(50, 1, "Hyprland", 300 << 20, 4.0),
            entry(60, 50, "firefox", 1700ULL << 20, 12.4),
            entry(61, 60, "Web Content", 400 << 20, 1.0),
            entry(62, 60, "web content", 450 << 20, 0.6),
            entry(63, 60, "GPU Process", 9000ULL << 20, 3.0), // larger than its parent
            entry(70, 50, "Zed", 720 << 20, 8.1, "me", "/usr/bin/zed --foreground"),
        };
        ViewOptions o;
        o.sort = SortKey::Memory;
        check(names(e, buildView(e, o)) == "GPU Process,firefox,Zed,web content,Web Content,Hyprland,systemd", "the list sorts by memory, largest first");
        o.sort = SortKey::Cpu;
        check(names(e, buildView(e, o)) == "firefox,Zed,Hyprland,GPU Process,Web Content,web content,systemd", "the list sorts by CPU, busiest first");
        o.sort = SortKey::Name;
        const auto byName = names(e, buildView(e, o));
        check(byName == "firefox,GPU Process,Hyprland,systemd,Web Content,web content,Zed", "the list sorts by name, ignoring case (" + byName + ")");
        o.sort = SortKey::Pid;
        check(names(e, buildView(e, o)) == "systemd,Hyprland,firefox,Web Content,web content,GPU Process,Zed", "the list sorts by PID");

        // Nearly equal values keep the order they had.
        std::vector<Entry> close = {entry(10, 1, "a", 100 << 20, 2.1), entry(11, 1, "b", (100 << 20) + 4096, 2.3)};
        std::unordered_map<std::string, std::size_t> rank = {{formatKey(close[0].id), 0}, {formatKey(close[1].id), 1}};
        ViewOptions st;
        st.sort = SortKey::Memory;
        st.previousRank = &rank;
        check(names(close, buildView(close, st)) == "a,b", "memory a few KiB apart keeps its previous order");
        st.sort = SortKey::Cpu;
        check(names(close, buildView(close, st)) == "a,b", "CPU a fraction of a percent apart keeps its previous order");
        rank = {{formatKey(close[0].id), 1}, {formatKey(close[1].id), 0}};
        check(names(close, buildView(close, st)) == "b,a", "and the previous order is what decides");

        // Search
        ViewOptions q;
        q.sort = SortKey::Pid;
        q.query = "WEB";
        check(names(e, buildView(e, q)) == "Web Content,web content", "search matches names, ignoring case");
        q.query = "70";
        check(names(e, buildView(e, q)) == "Zed", "search matches PIDs");
        q.query = "--foreground";
        check(names(e, buildView(e, q)) == "Zed", "search matches command lines");
        q.query = "root";
        check(names(e, buildView(e, q)) == "systemd", "search matches users");
        q.query = "  zed  ";
        check(names(e, buildView(e, q)) == "Zed", "surrounding spaces are ignored");
        q.query = "nothing-here";
        check(buildView(e, q).empty(), "a search with no match shows nothing");

        // Tree
        ViewOptions t;
        t.tree = true;
        t.sort = SortKey::Memory;
        const auto tree = buildView(e, t);
        check(names(e, tree, true) == "0systemd,1Hyprland,2firefox,3GPU Process,3web content,3Web Content,2Zed",
            "the tree follows real parents, with siblings in sort order (" + names(e, tree, true) + ")");
        check(tree[2].hasChildren && tree[2].expanded && !tree[3].hasChildren, "rows say whether they have children");
        std::unordered_set<std::string> collapsed = {formatKey(e[2].id)};
        t.collapsed = &collapsed;
        check(names(e, buildView(e, t)) == "systemd,Hyprland,firefox,Zed", "a collapsed process hides its children");
        check(!buildView(e, t)[2].expanded && buildView(e, t)[2].hasChildren, "and still shows that it has some");
        t.query = "gpu";
        const auto found = buildView(e, t);
        check(names(e, found) == "systemd,Hyprland,firefox,GPU Process", "searching the tree keeps a match's ancestors, opened");
        check(!found[0].match && !found[2].match && found[3].match, "ancestors shown only for placing are marked as such");

        // Bad parent data: a loop and a self-parent.
        std::vector<Entry> loop = {entry(5, 6, "x", 1), entry(6, 5, "y", 2), entry(7, 7, "z", 3)};
        ViewOptions lt;
        lt.tree = true;
        const auto lr = buildView(loop, lt);
        check(lr.size() == 3, "a parent loop in bad data is cut, and every process appears once");
    }

    if (root.rfind("/tmp/unnova-procfs-", 0) == 0) {
        std::filesystem::remove_all(root);
    }
    return failures == 0 ? 0 : 1;
}
