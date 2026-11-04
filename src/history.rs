use std::collections::VecDeque;

use crate::model::Workspace;

/// Snapshot-based undo/redo. Simple, robust, and plenty fast for a few
/// hundred cards per grid at the default 20-step cap.
///
/// `checkpoint` is called *before* a mutation with the state that is about to
/// change. The resulting state is recorded lazily by the next checkpoint or by
/// `undo`, so the history never needs to know the future.
pub struct History {
    entries: VecDeque<Workspace>,
    cursor: usize,
    limit: usize,
    pending: bool,
}

impl History {
    pub fn new(limit: usize, initial: Workspace) -> Self {
        let mut entries = VecDeque::new();
        entries.push_back(initial);
        Self {
            entries,
            cursor: 0,
            limit: limit.max(1),
            pending: false,
        }
    }

    pub fn set_limit(&mut self, limit: usize) {
        self.limit = limit.max(1);
        self.trim();
    }

    /// Record the state a new mutation is about to be applied to.
    pub fn checkpoint(&mut self, ws: &Workspace) {
        // A new edit invalidates any redo branch.
        if self.cursor + 1 < self.entries.len() {
            self.entries.truncate(self.cursor + 1);
        }
        // The previous mutation's result was not recorded yet; this checkpoint
        // is the first time we can observe it.
        if self.pending {
            self.entries.push_back(ws.clone());
            self.cursor = self.entries.len() - 1;
            self.trim();
        }
        self.pending = true;
    }

    pub fn can_undo(&self) -> bool {
        self.pending || self.cursor > 0
    }

    pub fn can_redo(&self) -> bool {
        !self.pending && self.cursor + 1 < self.entries.len()
    }

    /// `current` is the live workspace, which may contain edits that were not
    /// recorded by a following checkpoint yet.
    pub fn undo(&mut self, current: &Workspace) -> Option<Workspace> {
        if self.pending {
            self.entries.push_back(current.clone());
            self.cursor = self.entries.len() - 1;
            self.trim();
            self.pending = false;
        }
        if !self.can_undo() {
            return None;
        }
        self.cursor -= 1;
        self.entries.get(self.cursor).cloned()
    }

    pub fn redo(&mut self) -> Option<Workspace> {
        if !self.can_redo() {
            return None;
        }
        self.cursor += 1;
        self.entries.get(self.cursor).cloned()
    }

    pub fn reset(&mut self, ws: &Workspace) {
        self.entries.clear();
        self.entries.push_back(ws.clone());
        self.cursor = 0;
        self.pending = false;
    }

    fn trim(&mut self) {
        while self.entries.len() > self.limit + 1 {
            self.entries.pop_front();
            self.cursor = self.cursor.saturating_sub(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Workspace;

    #[test]
    fn undo_and_redo_restore_snapshots() {
        let ws0 = Workspace::default();
        let mut ws1 = ws0.clone();
        ws1.grids[0].name = "Second".into();
        let mut ws2 = ws1.clone();
        ws2.grids[0].name = "Third".into();

        let mut h = History::new(5, ws0.clone());
        h.checkpoint(&ws0);
        h.checkpoint(&ws1);

        assert_eq!(h.undo(&ws2).unwrap().grids[0].name, "Second");
        assert_eq!(h.undo(&ws1).unwrap().grids[0].name, "Grid A");
        assert_eq!(h.redo().unwrap().grids[0].name, "Second");
        assert_eq!(h.redo().unwrap().grids[0].name, "Third");
    }

    #[test]
    fn new_edit_after_undo_drops_redo_branch() {
        let ws0 = Workspace::default();
        let mut ws1 = ws0.clone();
        ws1.grids[0].name = "Second".into();
        let mut ws1b = ws0.clone();
        ws1b.grids[0].name = "Other".into();

        let mut h = History::new(5, ws0.clone());
        h.checkpoint(&ws0);
        assert_eq!(h.undo(&ws1).unwrap().grids[0].name, "Grid A");
        h.checkpoint(&ws0);
        let undone = h.undo(&ws1b).unwrap();
        assert_eq!(undone.grids[0].name, "Grid A");
        // The old redo branch is gone, but the new edit itself can be redone.
        assert!(!h.can_undo());
        assert_eq!(h.redo().unwrap().grids[0].name, "Other");
        assert!(!h.can_redo());
    }

    #[test]
    fn limit_drops_oldest() {
        let ws = Workspace::default();
        let mut current = ws.clone();
        let mut h = History::new(2, ws.clone());
        for i in 0..5 {
            h.checkpoint(&current);
            current.grids[0].name = format!("g{i}");
        }
        assert_eq!(h.undo(&current).unwrap().grids[0].name, "g3");
        assert_eq!(h.undo(&current).unwrap().grids[0].name, "g2");
    }
}
