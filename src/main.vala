/*
 * SPDX-FileCopyrightText: 2026 Iuri Suzano <iuri@astware.bar>
 * SPDX-License-Identifier: MIT
 *
 * Entry point for Amprev.
 */

namespace Astware.Amprev {
    public static int main (string[] args) {
        if (GLib.Environment.get_variable ("WEBKIT_DISABLE_COMPOSITING_MODE") == null) {
            GLib.Environment.set_variable ("WEBKIT_DISABLE_COMPOSITING_MODE", "1", false);
        }

        if (GLib.Environment.get_variable ("GSK_RENDERER") == null) {
            GLib.Environment.set_variable ("GSK_RENDERER", "cairo", false);
        }

        Gtk.Window.set_default_icon_name ("amprev");
        ensure_schema_dir ();

        var app = new Application ();
        return app.run (args);
    }

    private static void ensure_schema_dir () {
        if (GLib.Environment.get_variable ("GSETTINGS_SCHEMA_DIR") != null) {
            return;
        }

        string? schema_dir = GLib.Environment.get_variable ("AMPREV_SCHEMA_DIR");
        if (schema_dir == null || schema_dir == "") {
            schema_dir = schema_dir_from_binary ();
            if (schema_dir == null) {
                return;
            }
        }

        GLib.Environment.set_variable ("GSETTINGS_SCHEMA_DIR", schema_dir, false);
    }

    private static string? schema_dir_from_binary () {
        try {
            string exe_path = GLib.FileUtils.read_link ("/proc/self/exe");
            string exe_dir = GLib.Path.get_dirname (exe_path);
            string schema_dir = GLib.Path.build_filename (exe_dir, "..", "data");
            string compiled_schema = GLib.Path.build_filename (schema_dir, "gschemas.compiled");

            if (GLib.FileUtils.test (compiled_schema, GLib.FileTest.EXISTS)) {
                return schema_dir;
            }
        } catch (Error error) {
            warning ("schema bootstrap fallback failed: %s", error.message);
        }

        return null;
    }
}
