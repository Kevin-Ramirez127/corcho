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
