/*
 * SPDX-FileCopyrightText: 2026 Iuri Suzano <iuri@astware.bar>
 * SPDX-License-Identifier: MIT
 *
 * Application bootstrap and component wiring.
 */

namespace Astware.Amprev {
    /* Wires the runtime graph once and keeps the application bootstrap free of feature logic.
     * This class owns lifetime, resource loading, and service construction only.
     */
    public class Application : Adw.Application {
        private MainWindow? main_window;
        private Actions? actions;
        private Document? document;
        private MarkdownEngine? engine;
        private ExportService? export_service;
        private SyncService? sync_service;
        private ThemeService? theme_service;

        public Application () {
            Object (
                application_id: "bar.astware.amprev",
                flags: ApplicationFlags.DEFAULT_FLAGS
            );
        }

        protected override void activate () {
            if (main_window == null) {
                string resource_dir = runtime_resource_dir ();
                string style_path = GLib.Path.build_filename (resource_dir, "style.css");
                string css = read_text_or_fallback (style_path, default_css ());

                register_local_icon_theme ();

                document = new Document ();
                engine = new MarkdownEngine (css);
                export_service = new ExportService ();
                sync_service = new SyncService ();
                theme_service = new ThemeService ();

                main_window = new MainWindow (this, sync_service);
                actions = new Actions (
                    main_window,
                    document,
                    engine,
                    export_service,
                    sync_service,
                    theme_service
                );

                main_window.set_markdown ("");
            }

            main_window.present ();
        }

        private void register_local_icon_theme () {
            string? icon_dir = GLib.Environment.get_variable ("AMPREV_ICON_DIR");
            if (icon_dir == null || icon_dir == "") {
                icon_dir = icon_dir_from_binary ();
                if (icon_dir == null) {
                    return;
                }
            }

            if (!GLib.FileUtils.test (
                    GLib.Path.build_filename (icon_dir, "hicolor", "128x128", "apps", "amprev.png"),
                    GLib.FileTest.EXISTS)) {
                return;
            }

            var display = Gdk.Display.get_default ();
            if (display == null) {
                return;
            }

            Gtk.IconTheme.get_for_display (display).add_search_path (icon_dir);
        }

        private string? icon_dir_from_binary () {
            try {
                string exe_path = GLib.FileUtils.read_link ("/proc/self/exe");
                string exe_dir = GLib.Path.get_dirname (exe_path);
                string icon_dir = GLib.Path.build_filename (exe_dir, "..", "data", "icons");

                if (GLib.FileUtils.test (
                        GLib.Path.build_filename (icon_dir, "hicolor", "128x128", "apps", "amprev.png"),
                        GLib.FileTest.EXISTS)) {
                    return icon_dir;
                }
            } catch (Error error) {
                warning ("icon theme fallback failed: %s", error.message);
            }

            return null;
        }

        private string runtime_resource_dir () {
            string? resource_dir = GLib.Environment.get_variable ("AMPREV_RESOURCE_DIR");
            if (resource_dir != null && resource_dir != "") {
                return resource_dir;
            }

            return DATA_DIR;
        }

        private string read_text_or_fallback (string path, string fallback) {
            try {
                string contents;
                size_t length;
                if (GLib.FileUtils.get_contents (path, out contents, out length)) {
                    return contents;
                }
            } catch (Error error) {
                if (error is GLib.FileError) {
                    GLib.FileError file_error = (GLib.FileError) error;
                    if (file_error.code == GLib.FileError.NOENT) {
                        return fallback;
                    }
                }

                warning ("resource read fallback failed: %s", error.message);
            }

            return fallback;
        }

        private string get_default_theme_css () {
            return """
:root {
  color-scheme: light dark;
  --bg: #0f1115;
  --panel: #151922;
  --panel-alt: #11141b;
  --border: #2c3442;
  --text: #e6e9ef;
  --muted: #a9b0bf;
  --accent: #7aa2ff;
  --code-bg: #171b22;
  --quote-bg: #141821;
  --shadow: 0 10px 30px rgba(0, 0, 0, 0.26);
}

@media (prefers-color-scheme: light) {
  :root {
    --bg: #f6f8fa;
    --panel: #ffffff;
    --panel-alt: #fbfcfe;
    --border: #d0d7de;
    --text: #1f2328;
    --muted: #57606a;
    --accent: #0969da;
    --code-bg: #f6f8fa;
    --quote-bg: #f6f8fa;
    --shadow: 0 10px 30px rgba(31, 35, 40, 0.08);
  }
}

html, body {
  margin: 0;
  background: var(--bg);
  color: var(--text);
  font-family: "Inter", "Noto Sans", "Cantarell", sans-serif;
}

body {
  line-height: 1.6;
}

.markdown-body {
  max-width: 980px;
  margin: 0 auto;
  padding: 32px 40px 80px;
}

.markdown-body h1,
.markdown-body h2,
.markdown-body h3,
.markdown-body h4,
.markdown-body h5,
.markdown-body h6 {
  margin: 1.2em 0 0.4em;
  line-height: 1.25;
  font-weight: 700;
}

.markdown-body h1 {
  font-size: 2.15rem;
  border-bottom: 1px solid var(--border);
  padding-bottom: 0.35em;
}

.markdown-body h2 {
  font-size: 1.6rem;
  border-bottom: 1px solid var(--border);
  padding-bottom: 0.3em;
}

.markdown-body p {
  margin: 0.75em 0;
}

.markdown-body a {
  color: var(--accent);
  text-decoration: none;
}

.markdown-body a:hover {
  text-decoration: underline;
}

.markdown-body strong {
  font-weight: 700;
}

.markdown-body em {
  font-style: italic;
}

.markdown-body ul,
.markdown-body ol {
  padding-left: 1.5em;
  margin: 0.75em 0;
}

.markdown-body li + li {
  margin-top: 0.25em;
}

.markdown-body blockquote {
  margin: 1em 0;
  padding: 0.4em 1em;
  background: var(--quote-bg);
  border-left: 4px solid var(--border);
  color: var(--muted);
}

.markdown-body code {
  background: var(--code-bg);
  border: 1px solid rgba(208, 215, 222, 0.7);
  border-radius: 6px;
  padding: 0.15em 0.4em;
  font-family: "JetBrains Mono", "SFMono-Regular", "Consolas", monospace;
  font-size: 0.92em;
}

.markdown-body pre {
  background: var(--code-bg);
  border: 1px solid rgba(208, 215, 222, 0.7);
  border-radius: 12px;
  box-shadow: var(--shadow);
  overflow: auto;
  padding: 16px 18px;
}

.markdown-body pre code {
  background: transparent;
  border: 0;
  padding: 0;
  white-space: pre;
}

.markdown-body hr {
  border: 0;
  border-top: 1px solid var(--border);
  margin: 1.5em 0;
}

.markdown-body table {
  border-collapse: collapse;
}

.markdown-body td,
.markdown-body th {
  border: 1px solid var(--border);
  padding: 0.4em 0.7em;
}

.error-page {
  max-width: 780px;
  margin: 0 auto;
  padding: 48px 32px;
}

.error-page h1 {
  color: #cf222e;
}
""";
        }

        private string default_css () {
            return get_default_theme_css ();
        }

    }
}
