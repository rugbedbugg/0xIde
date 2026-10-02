#include "procfs.hpp"

#include <algorithm>
#include <cerrno>
#include <charconv>
#include <cmath>
#include <csignal>
#include <dirent.h>
#include <fcntl.h>
#include <limits>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

namespace caelestia::procfs {

namespace {

// Enough for every field this reads. A longer command line is cut, which only
// affects how much of it is shown and searched.
constexpr std::size_t k_maxFile = 64 * 1024;
// The kernel's PF_KTHREAD.
constexpr std::uint64_t k_kthreadFlag = 0x00200000;

std::optional<std::string> readFile(const std::string& path) {
    const int fd = ::open(path.c_str(), O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        return std::nullopt;
    }
    std::string out;
    char buf[4096];
    while (out.size() < k_maxFile) {
        const ssize_t n = ::read(fd, buf, sizeof buf);
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
            ::close(fd);
            return std::nullopt;
        }
        if (n == 0) {
            break;
        }
        out.append(buf, static_cast<std::size_t>(n));
    }
    ::close(fd);
    if (out.size() > k_maxFile) {
        out.resize(k_maxFile);
    }
    return out;
}

template <typename T> std::optional<T> number(std::string_view text) {
    T value{};
    const auto* end = text.data() + text.size();
    const auto [ptr, ec] = std::from_chars(text.data(), end, value);
    if (ec != std::errc() || ptr != end || text.empty()) {
        return std::nullopt;
    }
    return value;
}

bool allDigits(std::string_view text) {
    return !text.empty() && std::all_of(text.begin(), text.end(), [](char c) {
        return c >= '0' && c <= '9';
    });
}

std::vector<std::string_view> fields(std::string_view text) {
    std::vector<std::string_view> out;
    std::size_t i = 0;
    while (i < text.size()) {
        while (i < text.size() && (text[i] == ' ' || text[i] == '\n')) {
            ++i;
        }
        const std::size_t start = i;
        while (i < text.size() && text[i] != ' ' && text[i] != '\n') {
            ++i;
        }
        if (i > start) {
            out.push_back(text.substr(start, i - start));
        }
    }
    return out;
}

std::uint64_t pageSize() {
    static const auto size = static_cast<std::uint64_t>(std::max(1L, ::sysconf(_SC_PAGESIZE)));
    return size;
}

} // namespace

std::optional<Stat> parseStat(std::string_view text) {
    const auto open = text.find('(');
    const auto close = text.rfind(')');
    if (open == std::string_view::npos || close == std::string_view::npos || close < open || open < 2 ||
        text[open - 1] != ' ') {
        return std::nullopt;
    }
    const auto pid = number<pid_t>(text.substr(0, open - 1));
    if (!pid || *pid <= 0) {
        return std::nullopt;
    }
    const auto rest = fields(text.substr(close + 1));
    // state is field 3; starttime, field 22, is the last one needed.
    if (rest.size() < 20 || rest[0].size() != 1) {
        return std::nullopt;
    }
    const auto ppid = number<pid_t>(rest[1]);
    const auto flags = number<std::uint64_t>(rest[6]);
    const auto utime = number<std::uint64_t>(rest[11]);
    const auto stime = number<std::uint64_t>(rest[12]);
    const auto threads = number<long>(rest[17]);
    const auto start = number<std::uint64_t>(rest[19]);
    if (!ppid || *ppid < 0 || !flags || !utime || !stime || !threads || !start) {
        return std::nullopt;
    }
    Stat s;
    s.pid = *pid;
    s.comm = std::string(text.substr(open + 1, close - open - 1));
    s.state = rest[0][0];
    s.ppid = *ppid;
    s.flags = *flags;
    s.utime = *utime;
    s.stime = *stime;
    s.threads = *threads;
    s.startTime = *start;
    return s;
}

std::string formatKey(const Identity& id) {
    return std::to_string(id.pid) + ":" + std::to_string(id.startTime);
}

std::optional<Identity> parseKey(std::string_view key) {
    const auto colon = key.find(':');
    if (colon == std::string_view::npos) {
        return std::nullopt;
    }
    const auto pidText = key.substr(0, colon);
    const auto startText = key.substr(colon + 1);
    if (!allDigits(pidText) || !allDigits(startText)) {
        return std::nullopt;
    }
    const auto pid = number<pid_t>(pidText);
    const auto start = number<std::uint64_t>(startText);
    if (!pid || *pid <= 0 || !start) {
        return std::nullopt;
    }
    return Identity{*pid, *start};
}

Reader::Reader(std::string root)
    : m_root(std::move(root)) {}

std::optional<Sample> Reader::sample(pid_t pid) const {
    const std::string dir = m_root + "/" + std::to_string(pid);
    const auto statText = readFile(dir + "/stat");
    if (!statText) {
        return std::nullopt;
    }
    const auto stat = parseStat(*statText);
    if (!stat || stat->pid != pid) {
        return std::nullopt;
    }
    struct stat st {};
    if (::stat(dir.c_str(), &st) != 0) {
        return std::nullopt;
    }
    Sample s;
    s.id = {pid, stat->startTime};
    s.ppid = stat->ppid;
    s.state = stat->state;
    s.comm = stat->comm;
    s.uid = st.st_uid;
    s.threads = stat->threads;
    s.cpuTicks = stat->utime + stat->stime;
    s.kernelThread = (stat->flags & k_kthreadFlag) != 0;
    // Memory is optional: a process can be listed without it.
    if (const auto statm = readFile(dir + "/statm")) {
        const auto f = fields(*statm);
        if (f.size() >= 3) {
            s.residentBytes = number<std::uint64_t>(f[1]).value_or(0) * pageSize();
            s.sharedBytes = number<std::uint64_t>(f[2]).value_or(0) * pageSize();
        }
    }
    return s;
}

std::vector<Sample> Reader::scan() const {
    std::vector<Sample> out;
    DIR* dir = ::opendir(m_root.c_str());
    if (!dir) {
        return out;
    }
    while (const dirent* entry = ::readdir(dir)) {
        const std::string_view name(entry->d_name);
        if (!allDigits(name)) {
            continue;
        }
        const auto pid = number<pid_t>(name);
        if (!pid || *pid <= 0) {
            continue;
        }
        if (auto s = sample(*pid)) {
            out.push_back(std::move(*s));
        }
    }
    ::closedir(dir);
    return out;
}

std::optional<std::uint64_t> Reader::startTime(pid_t pid) const {
    if (pid <= 0) {
        return std::nullopt;
    }
    const auto text = readFile(m_root + "/" + std::to_string(pid) + "/stat");
    if (!text) {
        return std::nullopt;
    }
    const auto stat = parseStat(*text);
    if (!stat || stat->pid != pid) {
        return std::nullopt;
    }
    return stat->startTime;
}

std::optional<std::vector<std::string>> Reader::arguments(pid_t pid) const {
    const auto text = readFile(m_root + "/" + std::to_string(pid) + "/cmdline");
    if (!text) {
        return std::nullopt;
    }
    std::vector<std::string> args;
    std::size_t start = 0;
    while (start < text->size()) {
        auto end = text->find('\0', start);
        if (end == std::string::npos) {
            end = text->size();
        }
        args.emplace_back(text->substr(start, end - start));
        start = end + 1;
    }
    // Each NUL terminates an argument. Consecutive NULs are real empty args.
    return args;
}

std::optional<std::string> Reader::executable(pid_t pid) const {
    const std::string link = m_root + "/" + std::to_string(pid) + "/exe";
    std::string buf(4096, '\0');
    const ssize_t n = ::readlink(link.c_str(), buf.data(), buf.size());
    if (n <= 0) {
        return std::nullopt;
    }
    buf.resize(static_cast<std::size_t>(n));
    return buf;
}

std::optional<MemInfo> Reader::memInfo() const {
    const auto text = readFile(m_root + "/meminfo");
    if (!text) {
        return std::nullopt;
    }
    MemInfo info;
    bool total = false;
    std::size_t start = 0;
    while (start < text->size()) {
        auto end = text->find('\n', start);
        if (end == std::string::npos) {
            end = text->size();
        }
        const std::string_view line(text->data() + start, end - start);
        const auto f = fields(line);
        if (f.size() >= 2) {
            const auto kib = number<std::uint64_t>(f[1]);
            if (kib) {
                const std::uint64_t bytes = *kib * 1024;
                if (f[0] == "MemTotal:") {
                    info.total = bytes;
                    total = true;
                } else if (f[0] == "MemAvailable:") {
                    info.available = bytes;
                } else if (f[0] == "SwapTotal:") {
                    info.swapTotal = bytes;
                } else if (f[0] == "SwapFree:") {
                    info.swapFree = bytes;
                }
            }
        }
        start = end + 1;
    }
    if (!total) {
        return std::nullopt;
    }
    return info;
}

std::optional<std::uint64_t> Reader::bootTime() const {
    const auto text = readFile(m_root + "/stat");
    if (!text) {
        return std::nullopt;
    }
    const auto at = text->find("\nbtime ");
    if (at == std::string::npos) {
        return std::nullopt;
    }
    const auto end = text->find('\n', at + 7);
    return number<std::uint64_t>(std::string_view(*text).substr(at + 7, end == std::string::npos ? std::string::npos : end - at - 7));
}

std::string displayName(std::string_view comm, const std::vector<std::string>& args) {
    if (args.empty() || args[0].empty()) {
        return std::string(comm);
    }
    std::string_view first(args[0]);
    // A title some programs write over their arguments: keep the first word.
    if (const auto space = first.find(' '); space != std::string_view::npos && first.find('/') != 0) {
        first = first.substr(0, space);
    }
    if (const auto slash = first.rfind('/'); slash != std::string_view::npos) {
        first = first.substr(slash + 1);
    }
    // comm is the kernel's copy, cut at 15 bytes.
    if (comm.empty() || (comm.size() >= 15 && first.size() > comm.size() && first.substr(0, comm.size()) == comm)) {
        return std::string(first.empty() ? comm : first);
    }
    return std::string(comm);
}

std::string joinArguments(const std::vector<std::string>& args) {
    std::string out;
    for (const auto& a : args) {
        if (!out.empty()) {
            out += ' ';
        }
        out += a;
    }
    return out;
}

const std::vector<SignalSpec>& acceptedSignals() {
    static const std::vector<SignalSpec> list = {
        {SIGHUP, "HUP"},
        {SIGINT, "INT"},
        {SIGQUIT, "QUIT"},
        {SIGILL, "ILL"},
        {SIGTRAP, "TRAP"},
        {SIGABRT, "ABRT"},
        {SIGBUS, "BUS"},
        {SIGFPE, "FPE"},
        {SIGKILL, "KILL"},
        {SIGUSR1, "USR1"},
        {SIGSEGV, "SEGV"},
        {SIGUSR2, "USR2"},
        {SIGPIPE, "PIPE"},
        {SIGALRM, "ALRM"},
        {SIGTERM, "TERM"},
        {SIGCHLD, "CHLD"},
        {SIGCONT, "CONT"},
        {SIGSTOP, "STOP"},
        {SIGTSTP, "TSTP"},
        {SIGTTIN, "TTIN"},
        {SIGTTOU, "TTOU"},
        {SIGURG, "URG"},
        {SIGXCPU, "XCPU"},
        {SIGXFSZ, "XFSZ"},
        {SIGVTALRM, "VTALRM"},
        {SIGPROF, "PROF"},
        {SIGWINCH, "WINCH"},
        {SIGIO, "IO"},
        {SIGPWR, "PWR"},
        {SIGSYS, "SYS"},
    };
    return list;
}

std::optional<int> signalNumber(std::string_view name) {
    if (name.size() > 3 && name.substr(0, 3) == "SIG") {
        name.remove_prefix(3);
    }
    for (const auto& s : acceptedSignals()) {
        if (s.name == name) {
            return s.number;
        }
    }
    return std::nullopt;
}

std::string_view resultName(SignalResult result) {
    switch (result) {
    case SignalResult::Sent:
        return "sent";
    case SignalResult::Exited:
        return "exited";
    case SignalResult::Stale:
        return "stale";
    case SignalResult::PermissionDenied:
        return "permission";
    case SignalResult::InvalidSignal:
        return "invalid-signal";
    case SignalResult::InvalidIdentity:
        return "invalid-identity";
    case SignalResult::Failed:
        return "failed";
    }
    return "failed";
}

namespace {

int realSend(int pidfd, pid_t pid, int signal) {
    int rc;
#ifdef SYS_pidfd_send_signal
    if (pidfd >= 0) {
        rc = static_cast<int>(::syscall(SYS_pidfd_send_signal, pidfd, signal, nullptr, 0));
    } else
#endif
    {
        (void)pidfd;
        rc = ::kill(pid, signal);
    }
    return rc == 0 ? 0 : errno;
}

} // namespace

SignalResult sendSignal(const Reader& reader, const Identity& id, std::string_view signalName) {
    return sendSignal(reader, id, signalName, realSend);
}

SignalResult sendSignal(const Reader& reader, const Identity& id, std::string_view signalName, Sender sender) {
    const auto sig = signalNumber(signalName);
    if (!sig) {
        return SignalResult::InvalidSignal;
    }
    // 0 and negative PIDs address process groups or every process.
    if (id.pid <= 0) {
        return SignalResult::InvalidIdentity;
    }

    int fd = -1;
#ifdef SYS_pidfd_open
    fd = static_cast<int>(::syscall(SYS_pidfd_open, id.pid, 0));
    if (fd < 0 && errno == ESRCH) {
        return SignalResult::Exited;
    }
    if (fd < 0 && errno != ENOSYS) {
        return SignalResult::Failed;
    }
#endif

    // With the process pinned, its start time says whether it is the one meant.
    const auto start = reader.startTime(id.pid);
    if (!start || *start != id.startTime) {
        if (fd >= 0) {
            ::close(fd);
        }
        return start ? SignalResult::Stale : SignalResult::Exited;
    }

    const int err = sender ? sender(fd, id.pid, *sig) : EINVAL;
    if (fd >= 0) {
        ::close(fd);
    }
    if (err == 0) {
        return SignalResult::Sent;
    }
    if (err == EPERM) {
        return SignalResult::PermissionDenied;
    }
    if (err == ESRCH) {
        return SignalResult::Exited;
    }
    return SignalResult::Failed;
}

bool alive(const Reader& reader, const Identity& id) {
    const auto start = reader.startTime(id.pid);
    return start && *start == id.startTime;
}

std::optional<SortKey> sortKeyFromName(std::string_view name) {
    if (name == "memory") {
        return SortKey::Memory;
    }
    if (name == "cpu") {
        return SortKey::Cpu;
    }
    if (name == "name") {
        return SortKey::Name;
    }
    if (name == "pid") {
        return SortKey::Pid;
    }
    return std::nullopt;
}

std::string lowered(std::string_view text) {
    std::string out(text);
    for (auto& c : out) {
        if (c >= 'A' && c <= 'Z') {
            c = static_cast<char>(c - 'A' + 'a');
        }
    }
    return out;
}

bool matches(const Entry& entry, std::string_view loweredQuery) {
    if (loweredQuery.empty()) {
        return true;
    }
    if (std::to_string(entry.id.pid).find(loweredQuery) != std::string::npos) {
        return true;
    }
    for (const auto* field : {&entry.name, &entry.user, &entry.command}) {
        if (lowered(*field).find(loweredQuery) != std::string::npos) {
            return true;
        }
    }
    return false;
}

namespace {

// Values within the same bucket are treated as equal, and keep the order they
// had, so a fraction of a percent does not reshuffle the list every second.
long memoryBucket(std::uint64_t bytes) {
    return bytes == 0 ? -1 : static_cast<long>(std::floor(std::log(static_cast<double>(bytes)) / std::log(1.03)));
}

long cpuBucket(double percent) {
    return static_cast<long>(std::floor(std::max(0.0, percent) / 0.5));
}

std::string trimmed(std::string_view text) {
    const auto first = text.find_first_not_of(" \t\n");
    if (first == std::string_view::npos) {
        return {};
    }
    const auto last = text.find_last_not_of(" \t\n");
    return std::string(text.substr(first, last - first + 1));
}

} // namespace

std::vector<Row> buildView(const std::vector<Entry>& entries, const ViewOptions& options) {
    const std::size_t n = entries.size();
    const auto fold = options.caseFold ? options.caseFold : lowered;
    const std::string query = fold(trimmed(options.query));

    std::vector<std::string> keys(n);
    std::vector<std::string> names(n);
    for (std::size_t i = 0; i < n; ++i) {
        keys[i] = formatKey(entries[i].id);
        if (options.sort == SortKey::Name) {
            names[i] = fold(entries[i].name);
        }
    }
    const auto rank = [&](std::size_t i) {
        if (!options.previousRank) {
            return std::numeric_limits<std::size_t>::max();
        }
        const auto it = options.previousRank->find(keys[i]);
        return it == options.previousRank->end() ? std::numeric_limits<std::size_t>::max() : it->second;
    };
    const auto before = [&](std::size_t a, std::size_t b) {
        const Entry& x = entries[a];
        const Entry& y = entries[b];
        switch (options.sort) {
        case SortKey::Memory:
            if (const auto bx = memoryBucket(x.memory), by = memoryBucket(y.memory); bx != by) {
                return bx > by;
            }
            break;
        case SortKey::Cpu:
            if (const auto bx = cpuBucket(x.cpuSort), by = cpuBucket(y.cpuSort); bx != by) {
                return bx > by;
            }
            break;
        case SortKey::Name:
            if (names[a] != names[b]) {
                return names[a] < names[b];
            }
            break;
        case SortKey::Pid:
            return x.id.pid < y.id.pid;
        }
        if (const auto ra = rank(a), rb = rank(b); ra != rb) {
            return ra < rb;
        }
        return x.id.pid < y.id.pid;
    };

    std::vector<char> matched(n, 1);
    if (!query.empty()) {
        for (std::size_t i = 0; i < n; ++i) {
            const auto& e = entries[i];
            matched[i] = std::to_string(e.id.pid).find(query) != std::string::npos ||
                         fold(e.name).find(query) != std::string::npos ||
                         fold(e.user).find(query) != std::string::npos ||
                         fold(e.command).find(query) != std::string::npos;
        }
    }

    std::vector<Row> rows;
    if (!options.tree) {
        std::vector<std::size_t> order;
        for (std::size_t i = 0; i < n; ++i) {
            if (matched[i]) {
                order.push_back(i);
            }
        }
        std::stable_sort(order.begin(), order.end(), before);
        rows.reserve(order.size());
        for (const auto i : order) {
            rows.push_back({i, 0, false, false, true});
        }
        return rows;
    }

    // The tree comes from each process's real parent, never from names. A PID
    // seen twice (impossible from the kernel, possible in bad data) keeps the
    // first, and a parent link that loops is cut.
    std::unordered_map<pid_t, std::size_t> byPid;
    for (std::size_t i = 0; i < n; ++i) {
        byPid.emplace(entries[i].id.pid, i);
    }
    std::vector<long> parent(n, -1);
    for (std::size_t i = 0; i < n; ++i) {
        const auto it = byPid.find(entries[i].ppid);
        if (it != byPid.end() && it->second != i) {
            parent[i] = static_cast<long>(it->second);
        }
    }
    // Break cycles: walk up from each node; a node met twice on one walk has
    // its parent link cut.
    {
        std::vector<int> state(n, 0); // 0 unseen, 1 on the current walk, 2 done
        for (std::size_t i = 0; i < n; ++i) {
            std::vector<std::size_t> walk;
            long cur = static_cast<long>(i);
            while (cur >= 0 && state[static_cast<std::size_t>(cur)] == 0) {
                state[static_cast<std::size_t>(cur)] = 1;
                walk.push_back(static_cast<std::size_t>(cur));
                cur = parent[static_cast<std::size_t>(cur)];
            }
            if (cur >= 0 && state[static_cast<std::size_t>(cur)] == 1) {
                parent[static_cast<std::size_t>(cur)] = -1;
            }
            for (const auto w : walk) {
                state[w] = 2;
            }
        }
    }

    // While searching, a match's ancestors are shown too, so it stays in place.
    std::vector<char> visible(n, query.empty() ? 1 : 0);
    if (!query.empty()) {
        for (std::size_t i = 0; i < n; ++i) {
            if (!matched[i]) {
                continue;
            }
            long cur = static_cast<long>(i);
            while (cur >= 0 && !visible[static_cast<std::size_t>(cur)]) {
                visible[static_cast<std::size_t>(cur)] = 1;
                cur = parent[static_cast<std::size_t>(cur)];
            }
        }
    }

    std::vector<std::vector<std::size_t>> children(n);
    std::vector<std::size_t> roots;
    for (std::size_t i = 0; i < n; ++i) {
        if (!visible[i]) {
            continue;
        }
        if (parent[i] >= 0) {
            children[static_cast<std::size_t>(parent[i])].push_back(i);
        } else {
            roots.push_back(i);
        }
    }
    std::stable_sort(roots.begin(), roots.end(), before);
    for (auto& c : children) {
        std::stable_sort(c.begin(), c.end(), before);
    }

    // Depth first, without recursion.
    std::vector<std::pair<std::size_t, int>> stack;
    for (auto it = roots.rbegin(); it != roots.rend(); ++it) {
        stack.emplace_back(*it, 0);
    }
    while (!stack.empty()) {
        const auto [i, depth] = stack.back();
        stack.pop_back();
        const bool hasChildren = !children[i].empty();
        // Searching shows every match, so it opens what it has to.
        const bool expanded = hasChildren && (!query.empty() || !options.collapsed || !options.collapsed->contains(keys[i]));
        rows.push_back({i, depth, hasChildren, expanded, matched[i] != 0});
        if (expanded) {
            for (auto it = children[i].rbegin(); it != children[i].rend(); ++it) {
                stack.emplace_back(*it, depth + 1);
            }
        }
    }
    return rows;
}

} // namespace caelestia::procfs
