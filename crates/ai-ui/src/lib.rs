//! The AI surface of the Craft App Suite: the connections form, the status strip and the chat panel.
//!
//! Every app that talks to a model shows the same three things to the same user: where the model is
//! (and the key, in the OS keychain), what is happening while it answers, and the conversation
//! itself. Those are this crate. What differs per app - the system prompt, what the document context
//! is, what "insert" means - stays in the app, passed in through the arguments and callbacks of each
//! component. The crate never touches the network: the app starts its own client and feeds the panel.

#![deny(clippy::unwrap_used, clippy::expect_used, clippy::panic, clippy::unimplemented, clippy::todo, clippy::unreachable)]

pub mod chat;
pub mod connections;

/// The suite's close control: an X drawn with two strokes at the text size, frameless like the top-bar icons, so
/// it lines up with the title next to it (a letter "x" sits on the baseline and reads as text).
pub fn close_button(ui: &mut egui::Ui, tooltip: &str) -> egui::Response {
    let side = ui.text_style_height(&egui::TextStyle::Body).max(14.0);
    let (rect, response) = ui.allocate_exact_size(egui::vec2(side, side), egui::Sense::click());
    if ui.is_rect_visible(rect) {
        let visuals = ui.style().interact(&response);
        if response.hovered() {
            ui.painter().rect_filled(rect.expand(2.0), 3.0, visuals.weak_bg_fill);
        }
        let mark = rect.shrink(side * 0.25);
        let stroke = egui::Stroke::new(1.5, visuals.fg_stroke.color);
        ui.painter().line_segment([mark.left_top(), mark.right_bottom()], stroke);
        ui.painter().line_segment([mark.right_top(), mark.left_bottom()], stroke);
    }
    response.on_hover_text(tooltip)
}
pub mod policy;
pub mod strip;

pub use chat::{ChatAction, ChatLabels, ChatPanel};
pub use connections::{ConnectionDraft, ConnectionsIntent, ConnectionsPanel, Labels as ConnectionsLabels, Preset};
pub use policy::{ContextInfo, ContextKind, ContextSource, Line, Role, Side, Turns, WindowPolicy};
pub use strip::{StatusStrip, StripAction, StripLabels};
