//! The shared icons in egui: an image tinted with the text colour, and the icon button the suite's top bar
//! uses (theme, settings, AI). The app installs the SVG loader once at start
//! (`egui_extras::install_image_loaders`, `egui_extras` feature `svg`).

use std::collections::HashMap;
use std::sync::{Arc, OnceLock};

use egui::load::Bytes;
use egui::{Image, ImageSource, Response, Ui, Vec2};

use crate::{ALL, Icon, ThemeMode};

/// The size of a top-bar icon, in points (the SVG grid is 24, drawn at 16 like the reference apps).
pub const SIZE: f32 = 16.0;

/// The SVGs with a white stroke, so `tint` sets the final colour. Prepared once; lookups clone an `Arc`.
fn white() -> &'static HashMap<&'static str, Arc<[u8]>> {
    static SET: OnceLock<HashMap<&'static str, Arc<[u8]>>> = OnceLock::new();
    SET.get_or_init(|| {
        ALL.iter().map(|(name, bytes)| (*name, Arc::from(String::from_utf8_lossy(bytes).replace("currentColor", "white").into_bytes()))).collect()
    })
}

/// The icon as an egui image source; the URI is unique to the suite set, so it never clashes with an app catalog.
#[must_use]
pub fn source(icon: Icon) -> ImageSource<'static> {
    let bytes = white().get(icon.name()).cloned().unwrap_or_default();
    ImageSource::Bytes { uri: format!("bytes://craft-icons/{}.svg", icon.name()).into(), bytes: Bytes::Shared(bytes) }
}

/// The icon at `SIZE`, tinted with the text colour of `ui`.
#[must_use]
pub fn image(ui: &Ui, icon: Icon) -> Image<'static> {
    Image::new(source(icon)).fit_to_exact_size(Vec2::splat(SIZE)).tint(ui.visuals().text_color())
}

/// A frameless icon button with a tooltip (every icon-only control has one, translated by the app).
pub fn button(ui: &mut Ui, icon: Icon, tooltip: &str) -> Response {
    let image = image(ui, icon);
    ui.add(egui::Button::image(image).frame(false)).on_hover_text(tooltip)
}

/// The theme button of the top bar: shows the current mode and moves to the next one on click. `tooltip` is the
/// app's translation of "Theme: {current mode}". Returns true when the mode changed (the app applies and saves it).
pub fn theme_button(ui: &mut Ui, mode: &mut ThemeMode, tooltip: &str) -> bool {
    let clicked = button(ui, mode.icon(), tooltip).clicked();
    if clicked {
        *mode = mode.next();
    }
    clicked
}
