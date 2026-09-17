#include "airequest.hpp"

#include <qjsonarray.h>
#include <qjsondocument.h>
#include <qjsonobject.h>
#include <qjsonvalue.h>
#include <qloggingcategory.h>
#include <qnetworkrequest.h>

namespace {

Q_LOGGING_CATEGORY(lcAiRequest, "caelestia.airequest", QtInfoMsg)

} // namespace

namespace caelestia {

using Qt::StringLiterals::operator""_s;
using Qt::StringLiterals::operator""_ba;

AiRequest::AiRequest(QObject* parent)
    : QObject(parent)
    , m_manager(new QNetworkAccessManager(this))
    , m_reply(nullptr)
    , m_timeout(new QTimer(this)) {
    m_timeout->setSingleShot(true);
    QObject::connect(m_timeout, &QTimer::timeout, this, [this]() {
        if (m_reply)
            m_reply->abort();
    });
}

void AiRequest::send(const QUrl& url, const QString& payload, int timeoutMs) {
    if (m_reply) {
        qCWarning(lcAiRequest) << "send: a request is already in flight";
        return;
    }

    m_buffer.clear();
    m_text.clear();
    m_error.clear();
    m_status = u"loading"_s;

    if (!url.isValid() || url.scheme().isEmpty()) {
        settle(u"failed"_s, tr("The AI backend URL is not valid."));
        return;
    }

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json"_ba);
    request.setRawHeader("Accept"_ba, "text/event-stream"_ba);
    request.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::AlwaysNetwork);

    m_reply = m_manager->post(request, payload.toUtf8());

    QObject::connect(m_reply, &QNetworkReply::readyRead, this, [this]() {
        if (m_reply)
            consume(m_reply->readAll());
    });
    QObject::connect(m_reply, &QNetworkReply::finished, this, [this]() {
        auto* reply = m_reply;
        m_reply = nullptr;
        m_timeout->stop();
        reply->deleteLater();

        // cancel() already settled this request and cleared m_reply itself.
        if (m_status == u"stopped"_s) {
            emit changed();
            emit finished();
            return;
        }

        consume(reply->readAll());

        if (reply->error() == QNetworkReply::OperationCanceledError)
            settle(u"stopped"_s, tr("The request timed out."));
        else if (reply->error() != QNetworkReply::NoError)
            settle(u"failed"_s, reply->errorString());
        else
            settle(u"complete"_s);
    });

    if (timeoutMs > 0)
        m_timeout->start(timeoutMs);

    emit changed();
}

void AiRequest::cancel() {
    if (!m_reply)
        return;

    auto* reply = m_reply;
    m_reply = nullptr;
    m_timeout->stop();
    m_status = u"stopped"_s;
    // Keeps whatever was streamed so far; the popup shows it as a partial answer.
    reply->abort();
    reply->deleteLater();

    emit changed();
    emit finished();
}

// Server-sent events arrive split across arbitrary read boundaries, so hold the
// tail until a full line is available.
void AiRequest::consume(const QByteArray& chunk) {
    if (chunk.isEmpty())
        return;

    m_buffer.append(chunk);

    qsizetype newline = m_buffer.indexOf('\n');
    while (newline != -1) {
        QByteArray line = m_buffer.left(newline);
        m_buffer.remove(0, newline + 1);

        if (line.endsWith('\r'))
            line.chop(1);

        if (line.startsWith("data:"_ba))
            handleEvent(line.mid(5).trimmed());

        newline = m_buffer.indexOf('\n');
    }
}

void AiRequest::handleEvent(const QByteArray& payload) {
    if (payload.isEmpty())
        return;

    if (payload == "[DONE]"_ba) {
        settle(u"complete"_s);
        return;
    }

    QJsonParseError parseError;
    const auto doc = QJsonDocument::fromJson(payload, &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        qCWarning(lcAiRequest) << "handleEvent: ignoring malformed event" << parseError.errorString();
        return;
    }

    const auto object = doc.object();

    // A backend that refuses mid-stream reports the reason in place of a choice.
    if (const auto error = object.value(u"error"_s); error.isObject()) {
        settle(u"failed"_s, error.toObject().value(u"message"_s).toString(tr("The AI backend reported an error.")));
        return;
    }

    const auto choices = object.value(u"choices"_s).toArray();
    if (choices.isEmpty())
        return;

    const auto choice = choices.first().toObject();
    // Streaming responses carry "delta"; a backend that ignores stream:true
    // answers once with a whole "message" instead.
    QString content = choice.value(u"delta"_s).toObject().value(u"content"_s).toString();
    if (content.isEmpty())
        content = choice.value(u"message"_s).toObject().value(u"content"_s).toString();

    if (content.isEmpty())
        return;

    m_text += content;
    emit changed();
}

void AiRequest::settle(const QString& status, const QString& error) {
    // Exactly one terminal transition per request: a mid-stream error or a
    // [DONE] event settles it before the reply itself finishes.
    if (m_status != u"loading"_s)
        return;

    m_status = status;
    m_error = error;

    emit changed();
    emit finished();
}

} // namespace caelestia
