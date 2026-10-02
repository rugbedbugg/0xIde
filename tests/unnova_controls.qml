//@ pragma Env QML_IMPORT_PATH=@PLUGIN_QML@
import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.modules.unnova

// Actual controls with inert service substitutes. The window is never mapped.
// The runner also blocks uv so a default service cannot escape these mocks.
ShellRoot {
    id: test
    settings.watchFiles: false
    property var results: ({})
    property var calls: []
    function record(name) { calls = [...calls, name]; }
    function check(name, value) {
        results[name] = !!value;
        if (!value) console.log("FAIL " + name);
    }
    function descendants(o) {
        return (o.children ?? []).reduce((a, c) => a.concat([c], descendants(c)), []);
    }
    function named(name) { return descendants(win.contentItem).find(o => o.objectName === name); }
    QtObject {
        id: ai
        property var info: ({installed: true})
        property bool serving: false
        property bool stopping: false
        property bool installing: false
        property string endpoint: ""
        function start() { test.record("start"); }
        function stop() { test.record("stop"); }
        function restart() { test.record("restart"); }
    }
    QtObject {
        id: translation
        property bool translating: false
        function cancel() { test.record("cancel"); }
    }
    FloatingWindow {
        id: win
        visible: false
        implicitWidth: 640
        implicitHeight: 200
        contentItem.Tokens.screen: screen.name
        contentItem.Config.screen: screen.name
        RowLayout {
            anchors.fill: parent
            AiControls { runtime: ai }
            TranslationAction { translator: translation }
        }
    }
    Timer {
        interval: 500
        running: true
        onTriggered: {
            try {
                const toggle = named("aiStartStop"), restart = named("aiRestart"), cancel = named("translationCancel");
                check("opening controls starts no work", calls.length === 0);
                check("installed stopped AI offers Start", toggle.text === "Start" && !toggle.disabled && restart.disabled);
                toggle.clicked();
                check("Start delegates once to existing runtime", calls.join() === "start");
                ai.serving = true;
                check("starting server offers Unload but not Restart", toggle.text === "Unload" && !toggle.disabled && restart.disabled);
                restart.clicked();
                check("Restart is rejected before endpoint ready", calls.length === 1);
                toggle.clicked();
                check("Unload delegates while starting", calls.join() === "start,stop");
                ai.endpoint = "http://test";
                restart.clicked();
                check("ready server Restart delegates", !restart.disabled && calls.join() === "start,stop,restart");
                ai.stopping = true;
                toggle.clicked(); restart.clicked();
                check("stopping rejects stale clicks", toggle.disabled && restart.disabled && calls.length === 3);
                ai.stopping = false; ai.installing = true;
                toggle.clicked(); restart.clicked();
                check("model operation rejects runtime clicks", toggle.disabled && restart.disabled && calls.length === 3);
                ai.serving = false; ai.endpoint = "";
                toggle.clicked();
                check("installing model cannot start server", toggle.disabled && calls.length === 3);
                ai.installing = false; ai.info = {installed: false};
                toggle.clicked();
                check("missing model cannot start server", toggle.disabled && calls.length === 3);
                ai.info = {};
                toggle.clicked();
                check("unknown installation cannot start server", toggle.disabled && calls.length === 3);
                ai.info = {installed: true};
                check("Start re-enables after installation is known", !toggle.disabled);
                cancel.clicked();
                check("idle translation cannot be cancelled", cancel.disabled && calls.length === 3);
                translation.translating = true;
                cancel.clicked();
                check("active translation cancellation delegates once", !cancel.disabled && calls.join() === "start,stop,restart,cancel");
                translation.translating = false;
                cancel.clicked();
                check("finished translation rejects stale cancellation", cancel.disabled && calls.length === 4);
                console.log("RESULTS " + JSON.stringify(results));
            } catch (e) {
                console.log("FAIL " + e);
                console.log("RESULTS " + JSON.stringify(Object.assign({}, results, {completed: false})));
            }
            Qt.quit();
        }
    }
}
