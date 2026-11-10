import QtQuick
import "OverlayState.js" as OverlayState

// TapHandler for controls inside card bodies. Pointer events can be delivered
// to overlapping cards at the same time, so only run the action when the
// owning card is the top card at the tapped position.
TapHandler {
    id: root

    // Selection handlers (clicking a card body) select on purpose; ordinary
    // action controls must only run their action, without raising the card.
    property bool suppressSelection: true

    signal action()

    onPressedChanged: {
        if (!root.suppressSelection) return;
        var card = OverlayState.owningCard(root);
        if (!card) return;
        if (pressed) card.beginActionPress();
        else card.endActionPress();
    }

    onTapped: {
        var x = root.point.scenePosition.x;
        var y = root.point.scenePosition.y;
        if (!OverlayState.allowsCardAction(root, x, y))
            return;
        root.action();
    }
}
