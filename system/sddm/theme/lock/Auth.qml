import QtQuick

// The greeter's counterpart to the lockscreen's Pam.qml: the same key
// handling, with the password handed to SDDM instead of a PAM context.
QtObject {
    id: root

    enum State {
        Idle,
        Authenticating,
        Failed,
        Succeeded
    }

    property string buffer
    property int state: Auth.Idle
    property string user
    property bool userNeedsPassword: true
    property int sessionIndex
    property string infoMessage

    readonly property bool active: state === Auth.Authenticating

    // Flashes the message again when it has not changed, as Pam.flashMsg does.
    signal flashMsg

    function handleKey(event: var): void {
        if (active || state === Auth.Succeeded)
            return;

        if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
            submit();
        } else if (event.key === Qt.Key_Backspace) {
            buffer = event.modifiers & Qt.ControlModifier ? "" : buffer.slice(0, -1);
        } else if (event.key === Qt.Key_Escape) {
            buffer = "";
        } else if (/^[^\x00-\x1F\x7F-\x9F]+$/.test(event.text)) {
            // Allow anything except control characters
            buffer += event.text;
        }
    }

    function submit(): void {
        if (active || state === Auth.Succeeded || !user)
            return;
        if (!buffer && userNeedsPassword)
            return;
        infoMessage = "";
        state = Auth.Authenticating;
        sddm.login(user, buffer, sessionIndex);
    }

    // A change of user or session starts over: a message about the last
    // attempt says nothing about the next one.
    onUserChanged: {
        buffer = "";
        if (state === Auth.Failed)
            state = Auth.Idle;
    }

    readonly property Connections greeter: Connections {
        target: sddm

        function onLoginFailed(): void {
            root.buffer = "";
            if (root.state === Auth.Failed)
                root.flashMsg();
            root.state = Auth.Failed;
        }

        function onLoginSucceeded(): void {
            root.state = Auth.Succeeded;
        }

        function onInformationMessage(message: string): void {
            root.infoMessage = message;
        }
    }
}
