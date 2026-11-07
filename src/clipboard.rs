use std::slice;

unsafe extern "C" {
    fn corcho_clipboard_text(out_len: *mut i32) -> *mut u8;
    fn corcho_clipboard_image_png(
        out_len: *mut i32,
        out_width: *mut i32,
        out_height: *mut i32,
    ) -> *mut u8;
    fn corcho_clipboard_set_text(data: *const u8, len: i32) -> i32;
    fn corcho_clipboard_free(buffer: *mut u8);
}

pub enum ClipboardContent {
    Empty,
    Text(String),
    Image {
        png: Vec<u8>,
        width: u32,
        height: u32,
    },
}

unsafe fn take_bytes(ptr: *mut u8, len: i32) -> Option<Vec<u8>> {
    if ptr.is_null() || len <= 0 {
        if !ptr.is_null() {
            corcho_clipboard_free(ptr);
        }
        return None;
    }
    let bytes = slice::from_raw_parts(ptr, len as usize).to_vec();
    corcho_clipboard_free(ptr);
    Some(bytes)
}

/// Read the system clipboard, preferring images over text. Must run on the
/// Qt GUI thread because it touches QGuiApplication::clipboard().
pub fn read() -> ClipboardContent {
    unsafe {
        let mut len = 0;
        let mut width = 0;
        let mut height = 0;
        let image_ptr = corcho_clipboard_image_png(&mut len, &mut width, &mut height);
        if let Some(png) = take_bytes(image_ptr, len) {
            if width > 0 && height > 0 {
                return ClipboardContent::Image {
                    png,
                    width: width as u32,
                    height: height as u32,
                };
            }
        }

        let mut len = 0;
        let text_ptr = corcho_clipboard_text(&mut len);
        if let Some(bytes) = take_bytes(text_ptr, len) {
            if let Ok(text) = String::from_utf8(bytes) {
                if !text.trim().is_empty() {
                    return ClipboardContent::Text(text);
                }
            }
        }
        ClipboardContent::Empty
    }
}

/// Replace the system clipboard text. Must run on the Qt GUI thread.
pub fn write_text(text: &str) -> bool {
    let Ok(len) = i32::try_from(text.len()) else {
        return false;
    };
    unsafe { corcho_clipboard_set_text(text.as_ptr(), len) == 1 }
}
