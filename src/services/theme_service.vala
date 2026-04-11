/*
 * SPDX-FileCopyrightText: 2026 Iuri Suzano <iuri@astware.bar>
 * SPDX-License-Identifier: MIT
 *
 * Theme persistence and application color scheme control.
 */

namespace Astware.Amprev {
    public enum ThemeMode {
        SYSTEM,
        LIGHT,
        DARK
    }

    /* Owns the persisted appearance preference and pushes it into Adw.StyleManager.
     * The toolkit decides the actual palette when the mode is SYSTEM.
     */
    public class ThemeService : Object {
        private const string settings_schema_id = "bar.astware.amprev";
        private const string key_theme = "theme";

        private GLib.Settings settings;
        private Adw.StyleManager style_manager;
        private ThemeMode current_mode;

        public signal void mode_changed (ThemeMode mode);

        public ThemeService () {
            style_manager = Adw.StyleManager.get_default ();
            settings = new GLib.Settings (settings_schema_id);
            current_mode = mode_from_key (settings.get_string (key_theme));

            apply_mode (current_mode, false);

            settings.changed.connect ((key) => {
                if (key == key_theme) {
                    sync_from_settings ();
                }
            });
        }

        public ThemeMode mode {
            get {
                return current_mode;
            }
        }

        public unowned string mode_key {
            get {
                return mode_to_key (current_mode);
            }
        }

        public void set_mode (ThemeMode mode) {
            if (mode == current_mode) {
                return;
            }

            current_mode = mode;
            settings.set_string (key_theme, mode_to_key (mode));
            apply_mode (mode, true);
        }

        private void sync_from_settings () {
            ThemeMode desired_mode = mode_from_key (settings.get_string (key_theme));
            if (desired_mode == current_mode) {
                return;
            }

            current_mode = desired_mode;
            apply_mode (desired_mode, true);
        }

        private void apply_mode (ThemeMode mode, bool emit_signal) {
            style_manager.color_scheme = color_scheme_for (mode);

            if (emit_signal) {
                mode_changed (mode);
            }
        }

        private static Adw.ColorScheme color_scheme_for (ThemeMode mode) {
            switch (mode) {
            case ThemeMode.LIGHT:
                return Adw.ColorScheme.FORCE_LIGHT;
            case ThemeMode.DARK:
                return Adw.ColorScheme.FORCE_DARK;
            default:
                return Adw.ColorScheme.DEFAULT;
            }
        }

        public static ThemeMode mode_from_key (string key) {
            switch (key) {
            case "light":
                return ThemeMode.LIGHT;
            case "dark":
                return ThemeMode.DARK;
            default:
                return ThemeMode.SYSTEM;
            }
        }

        public static unowned string mode_to_key (ThemeMode mode) {
            switch (mode) {
            case ThemeMode.LIGHT:
                return "light";
            case ThemeMode.DARK:
                return "dark";
            default:
                return "system";
            }
        }
    }
}
