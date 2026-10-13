//@ pragma Env QML_IMPORT_PATH=@PLUGIN_QML@
import QtQuick
import QtTest
import Quickshell
import qs.modules.nexus

// Nexus's settings list scrolled to its end in a short window, then a real
// click on the search bar: it must reach the search bar, not a row scrolled
// up behind it. The window is offscreen; nothing is opened or changed.
ShellRoot {
    id: h

    settings.watchFiles: false

    property var r: ({})

    function find(item: Item, test: var): var {
        if (test(item))
            return item;
        for (let i = 0; i < item.children.length; i++) {
            const found = find(item.children[i], test);
            if (found)
                return found;
        }
        return null;
    }

    NexusState {
        id: testState

        currentPageIdx: 0
    }

    FloatingWindow {
        id: win

        implicitWidth: 460
        implicitHeight: 420

        Loader {
            id: paneLoader

            anchors.fill: parent
            anchors.margins: 16
            active: false

            sourceComponent: NavPane {
                nState: testState
            }
        }
    }

    TestEvent {
        id: events
    }

    Timer {
        interval: 200
        running: true
        onTriggered: paneLoader.active = true
    }

    // The wheel still scrolls the clipped list, and its fade still shows.
    Timer {
        interval: 1200
        running: true
        onTriggered: {
            const list = h.find(paneLoader.item, i => i.contentHeight !== undefined && i.contentY !== undefined);
            h.r.startsAtTop = list.contentY <= 0 && list.clip === true;
            const mid = list.mapToItem(win.contentItem, list.width / 2, list.height / 2);
            events.mouseWheel(win.contentItem, mid.x, mid.y, Qt.NoButton, Qt.NoModifier, 0, -360, -1);
            scrolled.start();
        }
    }

    Timer {
        id: scrolled

        interval: 1200
        onTriggered: {
            const list = h.find(paneLoader.item, i => i.contentHeight !== undefined && i.contentY !== undefined);
            h.r.wheelScrolls = list.contentY > 0;
            h.r.topFadeShowsWhenScrolled = list.layer.enabled && list.topFadeOpacity < 0.05;
            clickSearch.start();
        }
    }

    Timer {
        id: clickSearch

        interval: 100
        onTriggered: {
            const pane = paneLoader.item;
            const list = find(pane, i => i.contentHeight !== undefined && i.contentY !== undefined);
            const search = find(pane, i => i.placeholderText !== undefined);
            h.r.scrolls = list.contentHeight > list.height;
            list.contentY = list.contentHeight - list.height + list.bottomMargin;
            const at = search.mapToItem(win.contentItem, search.width / 2, search.height / 2);
            h.r.rowBehindSearchBar = list.contentY > list.topMargin;
            h.r.searchClickSent = events.mouseClick(win.contentItem, at.x, at.y, Qt.LeftButton, Qt.NoModifier, -1);
            check.start();
        }
    }

    Timer {
        id: check

        interval: 400
        onTriggered: {
            h.r.searchBarClickOpensNoPage = testState.currentPageIdx === 0;
            h.r.searchBarTakesTheClick = h.find(paneLoader.item, i => i.placeholderText !== undefined).activeFocus;
            // The control: a click on a row the list shows does open its page,
            // so a page left unchanged above means the click went elsewhere.
            const pane = paneLoader.item;
            const list = h.find(pane, i => i.contentHeight !== undefined && i.contentY !== undefined);
            const mid = list.mapToItem(win.contentItem, list.width / 2, list.height / 2);
            h.r.controlClickSent = events.mouseClick(win.contentItem, mid.x, mid.y, Qt.LeftButton, Qt.NoModifier, -1);
            control.start();
        }
    }

    Timer {
        id: control

        interval: 400
        onTriggered: {
            h.r.rowClickOpensItsPage = testState.currentPageIdx !== 0;
            console.log("RESULT " + JSON.stringify(h.r));
            Qt.quit();
        }
    }
}
