// Exercise Qt's notification contract through insertion, removal and reordering.
#include <QChar>
#include <QBitArray>
#include "../shell/plugin/src/processes.hpp"
#include <QAbstractItemModelTester>
#include <QCoreApplication>
#include <QSignalSpy>
#include <algorithm>
#include <cstdio>
#include <random>

int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    using Model = caelestia::services::ProcessModel;
    Model model;
    QAbstractItemModelTester tester(&model, QAbstractItemModelTester::FailureReportingMode::Fatal);
    QSignalSpy resets(&model, &QAbstractItemModel::modelReset);
    std::mt19937 random(42);
    QList<Model::Item> items;
    for (int round = 0; round < 400; ++round) {
        items.clear();
        for (int pid = 1; pid <= 120; ++pid) {
            if (random() % 4 == 0) continue;
            Model::Item item;
            item.pid = pid;
            item.key = QString::number(pid) + ":100";
            item.name = QString::number(round);
            item.memory = round * 4096;
            items.append(item);
        }
        std::shuffle(items.begin(), items.end(), random);
        model.apply(items, false);
        if (model.rowCount() != items.size()) return 1;
        for (int row = 0; row < items.size(); ++row) {
            const auto idx = model.index(row, 0);
            if (model.data(idx, Model::KeyRole).toString() != items[row].key ||
                model.data(idx, Model::NameRole).toString() != items[row].name ||
                model.data(idx, Model::MemoryRole).toLongLong() != items[row].memory) return 1;
        }
    }
    model.apply({}, false);
    if (model.rowCount() || resets.count()) return 1;
    std::puts("ok 400 changing snapshots obey Qt's model contract without resetting the model");
}
