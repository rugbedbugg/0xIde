#include "processes.hpp"

#include <algorithm>
#include <cmath>
#include <pwd.h>
#include <qdatetime.h>
#include <unistd.h>

namespace caelestia::services {

using Qt::StringLiterals::operator""_s;

// ProcessModel

ProcessModel::ProcessModel(QObject* parent)
    : QAbstractListModel(parent) {}

int ProcessModel::rowCount(const QModelIndex& parent) const {
    return parent.isValid() ? 0 : static_cast<int>(m_items.size());
}

QVariant ProcessModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size()) {
        return {};
    }
    const Item& item = m_items.at(index.row());
    switch (role) {
    case KeyRole:
        return item.key;
    case PidRole:
        return item.pid;
    case NameRole:
        return item.name;
    case UserRole:
        return item.user;
    case CommandRole:
        return item.command;
    case CpuRole:
        return item.cpuTenths / 10.0;
    case MemoryRole:
        return static_cast<qreal>(item.memory);
    case DepthRole:
        return item.depth;
    case HasChildrenRole:
        return item.hasChildren;
    case ExpandedRole:
        return item.expanded;
    case MatchRole:
        return item.match;
    default:
        return {};
    }
}

QHash<int, QByteArray> ProcessModel::roleNames() const {
    return {
        {KeyRole, "key"},
        {PidRole, "pid"},
        {NameRole, "name"},
        {UserRole, "user"},
        {CommandRole, "command"},
        {CpuRole, "cpu"},
        {MemoryRole, "memory"},
        {DepthRole, "depth"},
        {HasChildrenRole, "hasChildren"},
        {ExpandedRole, "expanded"},
        {MatchRole, "match"},
    };
}

void ProcessModel::apply(QList<Item> items, bool reset) {
    if (reset) {
        beginResetModel();
        m_items = std::move(items);
        endResetModel();
        return;
    }

    QSet<QString> wanted;
    wanted.reserve(items.size());
    for (const auto& item : items) {
        wanted.insert(item.key);
    }

    // Gone rows first, in runs, from the end so indices stay valid.
    for (qsizetype i = m_items.size() - 1; i >= 0;) {
        if (wanted.contains(m_items.at(i).key)) {
            --i;
            continue;
        }
        qsizetype first = i;
        while (first > 0 && !wanted.contains(m_items.at(first - 1).key)) {
            --first;
        }
        beginRemoveRows({}, static_cast<int>(first), static_cast<int>(i));
        m_items.remove(first, i - first + 1);
        endRemoveRows();
        i = first - 1;
    }

    // Then each target position in turn: already there, moved up from further
    // down, or new.
    for (qsizetype i = 0; i < items.size(); ++i) {
        const Item& want = items.at(i);
        if (i < m_items.size() && m_items.at(i).key == want.key) {
            Item& have = m_items[i];
            QList<int> roles;
            if (have.name != want.name) {
                roles << NameRole;
            }
            if (have.user != want.user) {
                roles << UserRole;
            }
            if (have.command != want.command) {
                roles << CommandRole;
            }
            if (have.cpuTenths != want.cpuTenths) {
                roles << CpuRole;
            }
            if (have.memory != want.memory) {
                roles << MemoryRole;
            }
            if (have.depth != want.depth) {
                roles << DepthRole;
            }
            if (have.hasChildren != want.hasChildren) {
                roles << HasChildrenRole;
            }
            if (have.expanded != want.expanded) {
                roles << ExpandedRole;
            }
            if (have.match != want.match) {
                roles << MatchRole;
            }
            if (!roles.isEmpty()) {
                have = want;
                const auto idx = index(static_cast<int>(i));
                emit dataChanged(idx, idx, roles);
            }
            continue;
        }
        qsizetype from = -1;
        for (qsizetype j = i + 1; j < m_items.size(); ++j) {
            if (m_items.at(j).key == want.key) {
                from = j;
                break;
            }
        }
        if (from >= 0) {
            beginMoveRows({}, static_cast<int>(from), static_cast<int>(from), {}, static_cast<int>(i));
            m_items.move(from, i);
            endMoveRows();
            m_items[i] = want;
            const auto idx = index(static_cast<int>(i));
            emit dataChanged(idx, idx);
        } else {
            beginInsertRows({}, static_cast<int>(i), static_cast<int>(i));
            m_items.insert(i, want);
            endInsertRows();
        }
    }
}

// Processes

Processes::Processes(QObject* parent)
    : Service(parent)
    , m_model(new ProcessModel(this))
    , m_cpuHistory(new CircularBuffer(this))
    , m_memoryHistory(new CircularBuffer(this)) {
    m_timer.setInterval(1000);
    m_timer.setTimerType(Qt::CoarseTimer);
    QObject::connect(&m_timer, &QTimer::timeout, this, &Processes::tick);
    m_clockTicks = std::max(1L, ::sysconf(_SC_CLK_TCK));
    m_cpus = std::max(1L, ::sysconf(_SC_NPROCESSORS_ONLN));
    m_cpuHistory->setCapacity(m_historyLength + 1);
    m_memoryHistory->setCapacity(m_historyLength + 1);
}

ProcessModel* Processes::model() const {
    return m_model;
}

bool Processes::active() const {
    return m_active;
}

int Processes::count() const {
    return static_cast<int>(m_entries.size());
}

int Processes::threadCount() const {
    return m_threads;
}

qreal Processes::swapUsed() const {
    return m_swapUsed;
}

qreal Processes::swapTotal() const {
    return m_swapTotal;
}

qreal Processes::sampleMs() const {
    return m_sampleMs;
}

int Processes::samples() const {
    return m_samples;
}

uint Processes::ownUid() const {
    return static_cast<uint>(::getuid());
}

QString Processes::query() const {
    return m_query;
}

void Processes::setQuery(const QString& query) {
    if (query == m_query) {
        return;
    }
    m_query = query;
    emit queryChanged();
    rebuild(false);
}

QString Processes::sortKey() const {
    return m_sortKey;
}

void Processes::setSortKey(const QString& key) {
    if (key == m_sortKey || !procfs::sortKeyFromName(key.toStdString())) {
        return;
    }
    m_sortKey = key;
    m_rank.clear();
    emit sortKeyChanged();
    rebuild(false);
}

bool Processes::treeMode() const {
    return m_treeMode;
}

void Processes::setTreeMode(bool tree) {
    if (tree == m_treeMode) {
        return;
    }
    m_treeMode = tree;
    m_rank.clear();
    emit treeModeChanged();
    rebuild(false);
}

QString Processes::selectedKey() const {
    return m_selectedKey;
}

void Processes::setSelectedKey(const QString& key) {
    if (key == m_selectedKey) {
        return;
    }
    m_selectedKey = key;
    m_selected.clear();
    m_selectedAlive = false;
    m_cpuHistory->clear();
    m_memoryHistory->clear();
    emit selectedKeyChanged();
    updateSelected();
    emit selectedChanged();
}

QVariantMap Processes::selected() const {
    return m_selected;
}

bool Processes::selectedAlive() const {
    return m_selectedAlive;
}

int Processes::historyLength() const {
    return m_historyLength;
}

CircularBuffer* Processes::cpuHistory() const {
    return m_cpuHistory;
}

CircularBuffer* Processes::memoryHistory() const {
    return m_memoryHistory;
}

void Processes::refresh() {
    if (m_active) {
        tick();
    }
}

void Processes::toggleExpanded(const QString& key) {
    const auto k = key.toStdString();
    if (!m_collapsed.erase(k)) {
        m_collapsed.insert(k);
    }
    rebuild(false);
}

bool Processes::isAlive(const QString& key) const {
    const auto id = procfs::parseKey(key.toStdString());
    return id && procfs::alive(m_reader, *id);
}

QVariantMap Processes::sendSignal(const QString& key, const QString& signal) {
    const auto id = procfs::parseKey(key.toStdString());
    const auto result = id ? procfs::sendSignal(m_reader, *id, signal.toStdString()) : procfs::SignalResult::InvalidIdentity;
    QString message;
    switch (result) {
    case procfs::SignalResult::Sent:
        break;
    case procfs::SignalResult::Exited:
        message = tr("The process has already exited.");
        break;
    case procfs::SignalResult::Stale:
        message = tr("That process has exited and its PID now belongs to another process. Nothing was sent.");
        break;
    case procfs::SignalResult::PermissionDenied:
        message = tr("You don't have permission to signal this process.");
        break;
    case procfs::SignalResult::InvalidSignal:
        message = tr("That is not a signal UnNova sends.");
        break;
    case procfs::SignalResult::InvalidIdentity:
        message = tr("That is not a valid process.");
        break;
    case procfs::SignalResult::Failed:
        message = tr("The signal could not be sent.");
        break;
    }
    // Show the effect promptly rather than at the next tick.
    if (result == procfs::SignalResult::Sent && m_active) {
        QTimer::singleShot(150, this, &Processes::refresh);
    }
    return {
        {u"result"_s, QString::fromLatin1(procfs::resultName(result))},
        {u"message"_s, message},
    };
}

QStringList Processes::signalNames() const {
    QStringList out;
    for (const auto& s : procfs::acceptedSignals()) {
        out << QString::fromLatin1(s.name);
    }
    return out;
}

QVariantMap Processes::usage(int pid) const {
    std::unordered_map<pid_t, std::vector<std::size_t>> children;
    std::size_t root = m_entries.size();
    for (std::size_t i = 0; i < m_entries.size(); ++i) {
        children[m_entries[i].ppid].push_back(i);
        if (m_entries[i].id.pid == pid) {
            root = i;
        }
    }
    if (pid <= 0 || root == m_entries.size()) {
        return {{u"found"_s, false}};
    }
    double cpu = 0;
    double memory = 0;
    int processes = 0;
    std::vector<std::size_t> stack{root};
    std::unordered_set<pid_t> seen;
    while (!stack.empty()) {
        const auto i = stack.back();
        stack.pop_back();
        const auto& e = m_entries[i];
        if (!seen.insert(e.id.pid).second) {
            continue;
        }
        cpu += e.cpu;
        memory += static_cast<double>(e.memory);
        ++processes;
        if (const auto it = children.find(e.id.pid); it != children.end()) {
            stack.insert(stack.end(), it->second.begin(), it->second.end());
        }
    }
    const auto& e = m_entries[root];
    const auto known = m_known.find(procfs::formatKey(e.id));
    return {
        {u"found"_s, true},
        {u"key"_s, QString::fromStdString(procfs::formatKey(e.id))},
        {u"name"_s, QString::fromStdString(e.name)},
        {u"command"_s, known != m_known.end() ? known->second.command : QString()},
        {u"cpu"_s, cpu},
        {u"memory"_s, memory},
        {u"processes"_s, processes},
    };
}

void Processes::start() {
    m_active = true;
    emit activeChanged();
    m_bootTime = m_reader.bootTime().value_or(0);
    m_clock.restart();
    m_lastTickMs = 0;
    tick();
    // CPU use is a difference between two samples; take the second one soon
    // instead of showing nothing for a whole interval.
    QTimer::singleShot(300, this, [this] {
        if (m_active) {
            tick();
            m_timer.start();
        }
    });
}

void Processes::stop() {
    m_active = false;
    m_timer.stop();
    // Nothing is kept for the next opening, which starts from a fresh sample.
    m_known.clear();
    m_entries.clear();
    m_rank.clear();
    m_collapsed.clear();
    m_collapsedKernel = false;
    m_query.clear();
    m_selectedKey.clear();
    m_selected.clear();
    m_selectedAlive = false;
    m_cpuHistory->clear();
    m_memoryHistory->clear();
    m_model->apply({}, true);
    emit activeChanged();
    emit queryChanged();
    emit selectedKeyChanged();
    emit selectedChanged();
}

QString Processes::userName(uid_t uid) {
    if (const auto it = m_users.constFind(uid); it != m_users.cend()) {
        return *it;
    }
    QString name = QString::number(uid);
    passwd pw{};
    passwd* found = nullptr;
    std::vector<char> buf(16384);
    if (::getpwuid_r(uid, &pw, buf.data(), buf.size(), &found) == 0 && found && found->pw_name) {
        name = QString::fromLocal8Bit(found->pw_name);
    }
    m_users.insert(uid, name);
    return name;
}

void Processes::tick() {
    QElapsedTimer cost;
    cost.start();

    const qint64 now = m_clock.elapsed();
    const qint64 elapsedMs = m_lastTickMs > 0 || m_samples > 0 ? now - m_lastTickMs : 0;
    m_lastTickMs = now;
    const double ticksAvailable = static_cast<double>(elapsedMs) / 1000.0 * static_cast<double>(m_clockTicks) * static_cast<double>(m_cpus);

    auto samples = m_reader.scan();
    std::unordered_map<std::string, Known> next;
    next.reserve(samples.size());
    m_entries.clear();
    m_entries.reserve(samples.size());
    m_threads = 0;

    for (auto& s : samples) {
        auto key = procfs::formatKey(s.id);
        Known k;
        bool fresh = true;
        if (auto it = m_known.find(key); it != m_known.end()) {
            k = std::move(it->second);
            fresh = false;
        }
        // exec and rewritten argv need not change comm. Read the bounded
        // command line each sample so search and runtime identification stay current.
        {
            const auto args = m_reader.arguments(s.id.pid);
            const std::vector<std::string> none;
            k.name = QString::fromStdString(procfs::displayName(s.comm, s.kernelThread || !args ? none : *args));
            k.command = args ? QString::fromStdString(procfs::joinArguments(*args)) : QString();
        }
        double cpu = 0;
        if (!fresh && ticksAvailable > 0 && s.cpuTicks >= k.sample.cpuTicks) {
            cpu = static_cast<double>(s.cpuTicks - k.sample.cpuTicks) / ticksAvailable * 100.0;
        }
        k.cpu = std::min(cpu, 100.0);
        k.cpuSort = fresh ? k.cpu : 0.5 * k.cpu + 0.5 * k.cpuSort;
        if (fresh || k.sample.uid != s.uid) {
            k.user = userName(s.uid);
        }
        k.sample = std::move(s);
        m_threads += static_cast<int>(std::max(0L, k.sample.threads));

        procfs::Entry e;
        e.id = k.sample.id;
        e.ppid = k.sample.ppid;
        e.name = k.name.toStdString();
        e.user = k.user.toStdString();
        e.command = k.command.toStdString();
        e.cpu = k.cpu;
        e.cpuSort = k.cpuSort;
        e.memory = k.sample.residentBytes > k.sample.sharedBytes ? k.sample.residentBytes - k.sample.sharedBytes : 0;
        m_entries.push_back(std::move(e));

        // Kernel threads start folded away, once; after that the choice is the user's.
        if (!m_collapsedKernel && k.sample.id.pid == 2 && k.sample.kernelThread) {
            m_collapsed.insert(key);
            m_collapsedKernel = true;
        }
        next.emplace(std::move(key), std::move(k));
    }
    m_known = std::move(next);

    for (auto it = m_collapsed.begin(); it != m_collapsed.end();) {
        it = m_known.contains(*it) ? std::next(it) : m_collapsed.erase(it);
    }

    if (const auto mem = m_reader.memInfo()) {
        m_swapTotal = static_cast<qreal>(mem->swapTotal);
        m_swapUsed = static_cast<qreal>(mem->swapTotal > mem->swapFree ? mem->swapTotal - mem->swapFree : 0);
    }

    rebuild(false);
    updateSelected();

    ++m_samples;
    m_sampleMs = static_cast<qreal>(cost.nsecsElapsed()) / 1e6;
    emit sampled();
}

void Processes::rebuild(bool reset) {
    const auto sort = procfs::sortKeyFromName(m_sortKey.toStdString()).value_or(procfs::SortKey::Memory);
    procfs::ViewOptions options;
    options.sort = sort;
    options.caseFold = [](std::string_view text) {
        return QString::fromUtf8(text.data(), static_cast<qsizetype>(text.size())).toCaseFolded().toStdString();
    };
    options.tree = m_treeMode;
    options.query = m_query.toStdString();
    options.collapsed = &m_collapsed;
    options.previousRank = &m_rank;
    const auto rows = procfs::buildView(m_entries, options);

    QList<ProcessModel::Item> items;
    items.reserve(static_cast<qsizetype>(rows.size()));
    std::unordered_map<std::string, std::size_t> rank;
    rank.reserve(rows.size());
    for (std::size_t r = 0; r < rows.size(); ++r) {
        const auto& row = rows[r];
        const auto& e = m_entries[row.entry];
        auto key = procfs::formatKey(e.id);
        const auto& k = m_known.at(key);
        ProcessModel::Item item;
        item.key = QString::fromStdString(key);
        item.pid = e.id.pid;
        item.name = k.name;
        item.user = k.user;
        item.command = k.command;
        // Rounded to what is shown, so an invisible change updates nothing.
        item.cpuTenths = static_cast<int>(std::lround(e.cpu * 10.0));
        item.memory = static_cast<qint64>(e.memory / (64 * 1024) * (64 * 1024));
        item.depth = row.depth;
        item.hasChildren = row.hasChildren;
        item.expanded = row.expanded;
        item.match = row.match;
        items << item;
        rank.emplace(std::move(key), r);
    }
    m_rank = std::move(rank);
    m_model->apply(std::move(items), reset);
}

void Processes::updateSelected() {
    if (m_selectedKey.isEmpty()) {
        return;
    }
    const auto it = m_known.find(m_selectedKey.toStdString());
    if (it == m_known.end()) {
        // Kept as it was last seen, marked as gone; never moved to another PID.
        if (m_selectedAlive || m_selected.isEmpty()) {
            m_selectedAlive = false;
            m_selected[u"alive"_s] = false;
            emit selectedChanged();
        }
        return;
    }
    const Known& k = it->second;
    const auto& s = k.sample;

    QVariantMap map;
    map[u"key"_s] = m_selectedKey;
    map[u"alive"_s] = true;
    map[u"pid"_s] = s.id.pid;
    map[u"ppid"_s] = s.ppid;
    map[u"name"_s] = k.name;
    map[u"comm"_s] = QString::fromStdString(s.comm);
    map[u"user"_s] = k.user;
    map[u"uid"_s] = static_cast<uint>(s.uid);
    map[u"state"_s] = QString(QChar::fromLatin1(s.state));
    map[u"threads"_s] = static_cast<int>(s.threads);
    map[u"cpu"_s] = k.cpu;
    const auto memory = s.residentBytes > s.sharedBytes ? s.residentBytes - s.sharedBytes : 0;
    map[u"memory"_s] = static_cast<qreal>(memory);
    map[u"resident"_s] = static_cast<qreal>(s.residentBytes);
    map[u"kernelThread"_s] = s.kernelThread;
    if (m_bootTime > 0) {
        const auto startedMs = static_cast<qint64>((static_cast<double>(m_bootTime) + static_cast<double>(s.id.startTime) / static_cast<double>(m_clockTicks)) * 1000.0);
        map[u"startedAt"_s] = QDateTime::fromMSecsSinceEpoch(startedMs);
        map[u"uptime"_s] = static_cast<qreal>(std::max<qint64>(0, QDateTime::currentMSecsSinceEpoch() - startedMs)) / 1000.0;
    }
    // The selected process's command line and executable are read every tick,
    // since a program can rewrite its title; for the rest, only on change.
    if (const auto args = m_reader.arguments(s.id.pid)) {
        map[u"command"_s] = QString::fromStdString(procfs::joinArguments(*args));
        map[u"commandReadable"_s] = true;
    } else {
        map[u"command"_s] = k.command;
        map[u"commandReadable"_s] = false;
    }
    if (const auto exe = m_reader.executable(s.id.pid)) {
        map[u"exe"_s] = QString::fromStdString(*exe);
        map[u"exeReadable"_s] = true;
    } else {
        map[u"exe"_s] = QString();
        map[u"exeReadable"_s] = false;
    }
    for (const auto& e : m_entries) {
        if (e.id.pid == s.ppid) {
            map[u"parentName"_s] = QString::fromStdString(e.name);
            map[u"parentKey"_s] = QString::fromStdString(procfs::formatKey(e.id));
            break;
        }
    }

    m_selected = map;
    m_selectedAlive = true;
    m_cpuHistory->push(k.cpu);
    m_memoryHistory->push(static_cast<qreal>(memory));
    emit selectedChanged();
}

} // namespace caelestia::services
