#pragma once

// UnNova's process service: the processes visible to this user, sampled once a
// second while something holds a ServiceRef to it, and nothing at all otherwise.
// It reads /proc itself, so a refresh starts no process. The list it builds
// keeps each row's identity across refreshes, so the view moves rows instead of
// rebuilding them.

#include <qabstractitemmodel.h>
#include <qelapsedtimer.h>
#include <qhash.h>
#include <qqmlintegration.h>
#include <qset.h>
#include <qtimer.h>
#include <qvariant.h>

#include <unordered_map>
#include <unordered_set>

#include "core/circularbuffer.hpp"
#include "procfs.hpp"
#include "service.hpp"

namespace caelestia::services {

class ProcessModel : public QAbstractListModel {
    Q_OBJECT
    QML_ANONYMOUS

public:
    enum Role {
        KeyRole = Qt::UserRole + 1,
        PidRole,
        NameRole,
        UserRole,
        CommandRole,
        CpuRole,
        MemoryRole,
        DepthRole,
        HasChildrenRole,
        ExpandedRole,
        MatchRole,
    };

    struct Item {
        QString key;
        int pid = 0;
        QString name;
        QString user;
        QString command;
        int cpuTenths = 0; // percent, to one decimal place
        qint64 memory = 0;
        int depth = 0;
        bool hasChildren = false;
        bool expanded = false;
        bool match = true;
    };

    explicit ProcessModel(QObject* parent = nullptr);

    [[nodiscard]] int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    [[nodiscard]] QVariant data(const QModelIndex& index, int role) const override;
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

    // Moves, inserts and removes rows to reach `items`, keyed by identity, so
    // the delegates of rows that stay are kept. `reset` rebuilds instead, for
    // a change of view where nearly every row moves.
    void apply(QList<Item> items, bool reset);

private:
    QList<Item> m_items;
};

class Processes : public Service {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(caelestia::services::ProcessModel* model READ model CONSTANT)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(int count READ count NOTIFY sampled)
    Q_PROPERTY(int threadCount READ threadCount NOTIFY sampled)
    Q_PROPERTY(qreal swapUsed READ swapUsed NOTIFY sampled)
    Q_PROPERTY(qreal swapTotal READ swapTotal NOTIFY sampled)
    Q_PROPERTY(qreal sampleMs READ sampleMs NOTIFY sampled)
    Q_PROPERTY(int samples READ samples NOTIFY sampled)
    Q_PROPERTY(uint ownUid READ ownUid CONSTANT)

    Q_PROPERTY(QString query READ query WRITE setQuery NOTIFY queryChanged)
    Q_PROPERTY(QString sortKey READ sortKey WRITE setSortKey NOTIFY sortKeyChanged)
    Q_PROPERTY(bool treeMode READ treeMode WRITE setTreeMode NOTIFY treeModeChanged)

    Q_PROPERTY(QString selectedKey READ selectedKey WRITE setSelectedKey NOTIFY selectedKeyChanged)
    Q_PROPERTY(QVariantMap selected READ selected NOTIFY selectedChanged)
    Q_PROPERTY(bool selectedAlive READ selectedAlive NOTIFY selectedChanged)
    Q_PROPERTY(int historyLength READ historyLength CONSTANT)
    Q_PROPERTY(caelestia::CircularBuffer* cpuHistory READ cpuHistory CONSTANT)
    Q_PROPERTY(caelestia::CircularBuffer* memoryHistory READ memoryHistory CONSTANT)

public:
    explicit Processes(QObject* parent = nullptr);

    [[nodiscard]] ProcessModel* model() const;
    [[nodiscard]] bool active() const;
    [[nodiscard]] int count() const;
    [[nodiscard]] int threadCount() const;
    [[nodiscard]] qreal swapUsed() const;
    [[nodiscard]] qreal swapTotal() const;
    [[nodiscard]] qreal sampleMs() const;
    [[nodiscard]] int samples() const;
    [[nodiscard]] uint ownUid() const;

    [[nodiscard]] QString query() const;
    void setQuery(const QString& query);
    [[nodiscard]] QString sortKey() const;
    void setSortKey(const QString& key);
    [[nodiscard]] bool treeMode() const;
    void setTreeMode(bool tree);

    [[nodiscard]] QString selectedKey() const;
    void setSelectedKey(const QString& key);
    [[nodiscard]] QVariantMap selected() const;
    [[nodiscard]] bool selectedAlive() const;
    [[nodiscard]] int historyLength() const;
    [[nodiscard]] CircularBuffer* cpuHistory() const;
    [[nodiscard]] CircularBuffer* memoryHistory() const;

    // Samples now rather than at the next tick. Does nothing while inactive.
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void toggleExpanded(const QString& key);
    // Whether the process `key` names still runs: same PID, same start time.
    Q_INVOKABLE bool isAlive(const QString& key) const;
    // { result, message }. result is one of procfs::resultName's values.
    Q_INVOKABLE QVariantMap sendSignal(const QString& key, const QString& signal);
    [[nodiscard]] Q_INVOKABLE QStringList signalNames() const;
    // A process and everything under it in the last sample: { found, key, name,
    // command, cpu, memory, processes }. For the 0xIde tab, which knows the PID
    // of what it started.
    [[nodiscard]] Q_INVOKABLE QVariantMap usage(int pid) const;

signals:
    void activeChanged();
    void sampled();
    void queryChanged();
    void sortKeyChanged();
    void treeModeChanged();
    void selectedKeyChanged();
    void selectedChanged();

private:
    struct Known {
        procfs::Sample sample;
        QString name;
        QString command;
        QString user;
        double cpu = 0;
        double cpuSort = 0;
    };

    void start() override;
    void stop() override;
    void tick();
    void rebuild(bool reset);
    void updateSelected();
    QString userName(uid_t uid);

    procfs::Reader m_reader;
    ProcessModel* m_model;
    QTimer m_timer;
    QElapsedTimer m_clock;
    qint64 m_lastTickMs = 0;
    bool m_active = false;
    int m_samples = 0;
    qreal m_sampleMs = 0;

    std::vector<procfs::Entry> m_entries;
    std::unordered_map<std::string, Known> m_known;
    std::unordered_map<std::string, std::size_t> m_rank;
    std::unordered_set<std::string> m_collapsed;
    bool m_collapsedKernel = false;
    QHash<uint, QString> m_users;
    int m_threads = 0;
    qreal m_swapUsed = 0;
    qreal m_swapTotal = 0;
    long m_clockTicks = 100;
    long m_cpus = 1;
    std::uint64_t m_bootTime = 0;

    QString m_query;
    QString m_sortKey = QStringLiteral("memory");
    bool m_treeMode = false;

    QString m_selectedKey;
    QVariantMap m_selected;
    bool m_selectedAlive = false;
    int m_historyLength = 60;
    CircularBuffer* m_cpuHistory;
    CircularBuffer* m_memoryHistory;
};

} // namespace caelestia::services
