// AiRequest against a local server that streams an answer and never ends it.
// cancel() mid-answer must settle once and keep the partial text. It used to
// crash the shell: abort() finishes the reply synchronously, and the finished
// handler then read the m_reply that cancel() had already cleared.
#include "airequest.hpp"
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QSignalSpy>
#include <QTcpServer>
#include <QTcpSocket>
#include <cstdio>
#include <functional>

namespace {

int failures = 0;

void check(bool passed, const char* what) {
    std::printf("%s %s\n", passed ? "ok" : "FAIL", what);
    // Flushed each time, so a crash still shows how far it got.
    std::fflush(stdout);
    if (!passed)
        ++failures;
}

bool waitFor(const std::function<bool()>& done, int ms = 5000) {
    QElapsedTimer timer;
    timer.start();
    while (!done()) {
        if (timer.elapsed() > ms)
            return false;
        QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
    }
    return true;
}

void settle(int ms) {
    waitFor([] { return false; }, ms);
}

} // namespace

int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    using caelestia::AiRequest;

    // Answers every request with one streamed chunk; ends the stream only when
    // finish is set, as a model that is still generating does not.
    bool finish = false;
    QTcpServer streaming;
    // Accepts and never answers, for the timeout.
    QTcpServer silent;
    if (!streaming.listen(QHostAddress::LocalHost) || !silent.listen(QHostAddress::LocalHost))
        return 2;
    QObject::connect(&streaming, &QTcpServer::newConnection, [&]() {
        while (auto* socket = streaming.nextPendingConnection()) {
            QObject::connect(socket, &QTcpSocket::readyRead, socket, [socket, &finish]() {
                socket->readAll();
                if (socket->property("answered").toBool())
                    return;
                socket->setProperty("answered", true);
                socket->write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n");
                socket->write("data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n");
                if (finish) {
                    socket->write("data: [DONE]\n\n");
                    socket->disconnectFromHost();
                }
                socket->flush();
            });
        }
    });
    const QUrl streamUrl(QStringLiteral("http://127.0.0.1:%1/v1/chat/completions").arg(streaming.serverPort()));
    const QUrl silentUrl(QStringLiteral("http://127.0.0.1:%1/v1/chat/completions").arg(silent.serverPort()));

    AiRequest request;
    QSignalSpy finished(&request, &AiRequest::finished);

    request.cancel();
    check(finished.count() == 0 && !request.running(), "cancel with nothing in flight does nothing");

    request.send(streamUrl, QStringLiteral("{}"));
    check(waitFor([&] { return request.text() == QStringLiteral("Hello"); }), "the streamed chunk arrives");
    request.cancel();
    check(request.status() == QStringLiteral("stopped") && !request.running(), "cancel mid-answer stops the request");
    check(request.text() == QStringLiteral("Hello"), "and keeps the partial answer");
    settle(300);
    check(finished.count() == 1, "and settles exactly once");

    finish = true;
    request.send(streamUrl, QStringLiteral("{}"));
    check(waitFor([&] { return request.status() != QStringLiteral("loading"); }) &&
              request.status() == QStringLiteral("complete") && request.text() == QStringLiteral("Hello"),
        "a request after a cancel completes");
    settle(300);
    check(finished.count() == 2 && !request.running(), "and settles once");

    request.send(silentUrl, QStringLiteral("{}"), 200);
    check(waitFor([&] { return request.status() != QStringLiteral("loading"); }) &&
              request.status() == QStringLiteral("stopped") &&
              request.error() == QStringLiteral("The request timed out."),
        "a stalled request times out");
    settle(300);
    check(finished.count() == 3 && !request.running(), "and settles once");

    // A panel torn down mid-answer destroys its request with the reply open.
    finish = false;
    auto* doomed = new AiRequest;
    doomed->send(streamUrl, QStringLiteral("{}"));
    waitFor([&] { return doomed->text() == QStringLiteral("Hello"); });
    doomed->cancel();
    delete doomed;
    settle(300);
    check(true, "a request cancelled and destroyed mid-answer is gone without a crash");

    return failures == 0 ? 0 : 1;
}
