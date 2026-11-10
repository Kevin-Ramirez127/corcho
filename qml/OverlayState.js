.pragma library

// Shared state for popups that float above the canvas. A menu is modal in
// practice: while one is open, clicks must not reach cards or the canvas
// underneath it, even when the menu is drawn over another card.
var openMenus = 0;

function menuOpened() {
    openMenus += 1;
}

function menuClosed() {
    if (openMenus > 0)
        openMenus -= 1;
}

// The CardFrame that owns an item, or null for controls outside cards.
function owningCard(item) {
    var p = item ? item.parent : null;
    while (p) {
        if (p.canvasView !== undefined && p.card !== undefined
                && typeof p.requestBodySelect === "function")
            return p;
        p = p.parent;
    }
    return null;
}

// True when an action at the given scene position belongs to this card.
// Overlapping cards can all receive a pointer event, so each action checks
// that its own card is the top one at that spot before doing anything.
function allowsCardAction(item, sceneX, sceneY) {
    if (openMenus > 0) return false;
    var card = owningCard(item);
    if (!card || !card.canvasView || !card.card) return true;
    return card.canvasView.isTopCardAtScene(card.card.id, sceneX, sceneY);
}
