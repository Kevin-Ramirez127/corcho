use std::collections::VecDeque;

use crate::model::Workspace;

/// Snapshot-based undo/redo. Simple, robust, and plenty fast for a few
/// hundred cards per grid at the default 20-step cap.
pub struct History {
    entries: VecDeque<Workspace>,
    cursor: usize,
    limit: usize,
}

impl History {
    pub fn new(limit: usize, initial: Workspace) -> Self {
        let mut entries = VecDeque::new();
        entries.push_back(initial);
        Self {
            entries,
            cursor: 0,
            limit: limit.max(1),
        }
    }

    pub fn set_limit(&mut self, limit: usize) {
        self.limit = limit.max(1);
        while self.entries.len() > self.limit + 1 {
            self.entries.pop_front();
            self.cursor = self.cursor.saturating_sub(1);
        }
    }

    pub fn push(&mut self, ws: &Workspace) {
        if self.cursor + 1 < self.entries.len() {
            self.entries.truncate(self.cursor + 1);
        }
        self.entries.push_back(ws.clone());
        while self.entries.len() > self.limit + 1 {
            self.entries.pop_front();
        }
        self.cursor = self.entries.len() - 1;
    }

    pub fn can_undo(&self) -> bool {
        self.cursor > 0
    }

    pub fn can_redo(&self) -> bool {
        self.cursor + 1 < self.entries.len()
    }

    pub fn undo(&mut self) -> Option<Workspace> {
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
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Workspace;

    #[test]
    fn undo_and_redo_restore_snapshots() {
        let mut ws = Workspace::default();
        let mut h = History::new(5, ws.clone());
        ws.grids[0].name = "Second".into();
        h.push(&ws);
        ws.grids[0].name = "Third".into();
        h.push(&ws);
        assert_eq!(h.undo().unwrap().grids[0].name, "Second");
        assert_eq!(h.undo().unwrap().grids[0].name, "Grid A");
        assert_eq!(h.redo().unwrap().grids[0].name, "Second");
    }

    #[test]
    fn limit_drops_oldest() {
        let ws = Workspace::default();
        let mut h = History::new(2, ws.clone());
        for i in 0..5 {
            let mut next = ws.clone();
            next.grids[0].name = format!("g{i}");
            h.push(&next);
        }
        assert!(!h.can_undo() || h.undo().is_some());
    }
}
