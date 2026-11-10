import QtQuick
import "OverlayState.js" as OverlayState

// TapHandler for controls inside card bodies. Pointer events can be delivered
// to overlapping cards at the same time, so only run the action when the
// owning card is the top card at the tapped position.
TapHandler {
    id: root

    signal action(var point)

    onTapped: {
        var x = root.point.scenePosition.x;
        var y = root.point.scenePosition.y;
        if (!OverlayState.allowsCardAction(root, x, y))
            return;
        // Actions are part of the card, so they also select it like a click
        // on the card surface would.
        var card = OverlayState.owningCard(root);
        if (card && (root.acceptedButtons & Qt.LeftButton))
            card.requestBodySelect(root.point.modifiers, x, y);
        root.action(root.point);
    }
}
