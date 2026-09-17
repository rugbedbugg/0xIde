#pragma once

#include <qnetworkaccessmanager.h>
#include <qnetworkreply.h>
#include <qobject.h>
#include <qqmlengine.h>
#include <qtimer.h>

namespace caelestia {

class AiRequest : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool running READ running NOTIFY changed)
    Q_PROPERTY(QString text READ text NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)

public:
    explicit AiRequest(QObject* parent = nullptr);

    [[nodiscard]] bool running() const { return m_reply != nullptr; }
    [[nodiscard]] QString text() const { return m_text; }
    [[nodiscard]] QString error() const { return m_error; }
    [[nodiscard]] QString status() const { return m_status; }

    // Sends an OpenAI-compatible chat completion. The payload should request
    // streaming; partial content is appended to `text` as it arrives. A
    // timeoutMs of 0 disables the timeout, leaving cancel() as the only way
    // to stop a stalled request.
    Q_INVOKABLE void send(const QUrl& url, const QString& payload, int timeoutMs = 0);
    Q_INVOKABLE void cancel();

signals:
    void changed();
    void finished();

private:
    QNetworkAccessManager* m_manager;
    QNetworkReply* m_reply;
    QTimer* m_timeout;
    QByteArray m_buffer;
    QString m_text;
    QString m_error;
    QString m_status;

    void consume(const QByteArray& chunk);
    void handleEvent(const QByteArray& payload);
    void settle(const QString& status, const QString& error = QString());
};

} // namespace caelestia
