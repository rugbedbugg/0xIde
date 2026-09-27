#pragma once

#include "settings/objectnode.hpp"
#include "common.hpp"

namespace caelestia::config {

using Qt::StringLiterals::operator""_s;

class AiConfig : public settings::ObjectNode {
    CONFIG_NODE(AiConfig, settings::ObjectNode)

    CONFIG_GLOBAL_PROPERTY(QString, backend, QString())
    CONFIG_GLOBAL_PROPERTY(QString, ocrLanguages, QString())
    CONFIG_GLOBAL_PROPERTY(bool, tableMode, false)
    CONFIG_GLOBAL_PROPERTY(QString, translateFrom, u"en"_s)
    CONFIG_GLOBAL_PROPERTY(QString, translateLanguage, QString())
    CONFIG_GLOBAL_PROPERTY(QString, backendUrl, u"http://127.0.0.1:8080/v1/chat/completions"_s)
    CONFIG_GLOBAL_PROPERTY(QString, model, QString())
    CONFIG_GLOBAL_PROPERTY(QString, systemPrompt, QString())
    CONFIG_GLOBAL_PROPERTY(QString, dictationLanguage, u"auto"_s)
};

} // namespace caelestia::config
