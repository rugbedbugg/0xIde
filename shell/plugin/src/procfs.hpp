#pragma once

// UnNova's view of /proc, with no Qt in it, so tests/run can compile and drive
// it directly. Everything here reads files; nothing starts a process.
//
// A PID alone is not an identity: the kernel reuses PIDs. A process is its PID
// together with the start time /proc/<pid>/stat records, and nothing is ever
// signalled without first checking that pair again.

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <sys/types.h>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace caelestia::procfs {

// The fields of /proc/<pid>/stat this uses.
struct Stat {
    pid_t pid = 0;
    std::string comm;
    char state = '?';
    pid_t ppid = 0;
    std::uint64_t flags = 0;
    std::uint64_t utime = 0; // clock ticks
    std::uint64_t stime = 0;
    long threads = 0;
    std::uint64_t startTime = 0; // clock ticks after boot
};

// comm may hold spaces and parentheses, so the fields after it are found from
// the last ')'. Anything malformed is nullopt rather than a guess.
std::optional<Stat> parseStat(std::string_view text);

struct Identity {
    pid_t pid = 0;
    std::uint64_t startTime = 0;

    bool operator==(const Identity&) const = default;
};

// "pid:starttime", the form the UI holds on to.
std::string formatKey(const Identity& id);
// Strict: decimal digits only, a positive PID, nothing else.
std::optional<Identity> parseKey(std::string_view key);

struct Sample {
    Identity id;
    pid_t ppid = 0;
    char state = '?';
    std::string comm;
    uid_t uid = 0;
    long threads = 0;
    std::uint64_t cpuTicks = 0;
    std::uint64_t residentBytes = 0;
    std::uint64_t sharedBytes = 0;
    bool kernelThread = false;
};

struct MemInfo {
    std::uint64_t total = 0;
    std::uint64_t available = 0;
    std::uint64_t swapTotal = 0;
    std::uint64_t swapFree = 0;
};

class Reader {
public:
    explicit Reader(std::string root = "/proc");

    [[nodiscard]] const std::string& root() const { return m_root; }

    // Every process that could be read. One that exits mid-scan, or whose
    // files cannot be read, is left out rather than failing the scan.
    [[nodiscard]] std::vector<Sample> scan() const;
    [[nodiscard]] std::optional<Sample> sample(pid_t pid) const;
    [[nodiscard]] std::optional<std::uint64_t> startTime(pid_t pid) const;
    // The arguments, NUL-separated as the kernel keeps them. Empty for a kernel
    // thread; nullopt when unreadable.
    [[nodiscard]] std::optional<std::vector<std::string>> arguments(pid_t pid) const;
    [[nodiscard]] std::optional<std::string> executable(pid_t pid) const;
    [[nodiscard]] std::optional<MemInfo> memInfo() const;
    // Seconds since the epoch at boot, from /proc/stat.
    [[nodiscard]] std::optional<std::uint64_t> bootTime() const;

private:
    std::string m_root;
};

// What the list shows for a process. comm is cut at 15 bytes, so when it is the
// start of the program's own name the full name is used instead.
std::string displayName(std::string_view comm, const std::vector<std::string>& args);
// The arguments joined by spaces, for display and search. Never executed.
std::string joinArguments(const std::vector<std::string>& args);

// Signals. The caller names one; the number always comes from this table, so
// nothing outside it can be sent.
struct SignalSpec {
    int number;
    std::string_view name; // without "SIG"
};
const std::vector<SignalSpec>& acceptedSignals();
std::optional<int> signalNumber(std::string_view name); // "TERM" or "SIGTERM"

enum class SignalResult {
    Sent,
    Exited,           // nothing has that PID any more
    Stale,            // the PID now belongs to a different process
    PermissionDenied,
    InvalidSignal,
    InvalidIdentity,
    Failed,
};
std::string_view resultName(SignalResult result);

// Sends a named signal to exactly the process `id` names. The process is pinned
// with a pidfd before its start time is checked, so it cannot be swapped for a
// newer one between the check and the signal. Without pidfds it falls back to
// the check followed by kill(2).
SignalResult sendSignal(const Reader& reader, const Identity& id, std::string_view signalName);

// The last step alone, for tests: returns 0 or an errno. The real one uses the
// pidfd when there is one (fd >= 0) and kill(2) otherwise.
using Sender = int (*)(int pidfd, pid_t pid, int signal);
SignalResult sendSignal(const Reader& reader, const Identity& id, std::string_view signalName, Sender sender);

// Whether the process `id` names is still running.
bool alive(const Reader& reader, const Identity& id);

// Building the list from a snapshot.
struct Entry {
    Identity id;
    pid_t ppid = 0;
    std::string name;
    std::string user;
    std::string command;
    double cpu = 0;      // what is shown
    double cpuSort = 0;  // smoothed, so the order is calm
    std::uint64_t memory = 0;
};

enum class SortKey { Memory, Cpu, Name, Pid };
std::optional<SortKey> sortKeyFromName(std::string_view name);

struct Row {
    std::size_t entry; // index into the snapshot
    int depth = 0;
    bool hasChildren = false;
    bool expanded = false;
    bool match = true; // false for an ancestor shown only to place a match
};

struct ViewOptions {
    // The Qt service supplies Unicode case folding; standalone users default
    // to the ASCII implementation below.
    std::string (*caseFold)(std::string_view) = nullptr;
    SortKey sort = SortKey::Memory;
    bool tree = false;
    std::string query;
    const std::unordered_set<std::string>* collapsed = nullptr; // keys
    // Where each key sat last time, so equal values keep their places.
    const std::unordered_map<std::string, std::size_t>* previousRank = nullptr;
};

// ASCII case-insensitive; bytes above 0x7f are compared as they are.
std::string lowered(std::string_view text);
bool matches(const Entry& entry, std::string_view loweredQuery);

std::vector<Row> buildView(const std::vector<Entry>& entries, const ViewOptions& options);

} // namespace caelestia::procfs
