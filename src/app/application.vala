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
                string github_markdown_css_path = GLib.Path.build_filename (resource_dir, "github-markdown.css");

                string css = read_text_or_fallback (style_path, get_default_theme_css ());
                string github_css = read_text_or_fallback (github_markdown_css_path, "");

                register_local_icon_theme ();

                document = new Document ();
                engine = new MarkdownEngine (css, github_css);
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
            if (resource_dir != null && resource_dir != "" && has_preview_resources (resource_dir)) {
                return resource_dir;
            }

            if (has_preview_resources (DATA_DIR)) {
                return DATA_DIR;
            }

            string? local_resource_dir = local_resource_dir_from_binary ();
            if (local_resource_dir != null) {
                return local_resource_dir;
            }

            return DATA_DIR;
        }

        private bool has_preview_resources (string resource_dir) {
            return GLib.FileUtils.test (
                GLib.Path.build_filename (resource_dir, "style.css"),
                GLib.FileTest.EXISTS
            ) && GLib.FileUtils.test (
                GLib.Path.build_filename (resource_dir, "github-markdown.css"),
                GLib.FileTest.EXISTS
            );
        }

        private string? local_resource_dir_from_binary () {
            try {
                string exe_path = GLib.FileUtils.read_link ("/proc/self/exe");
                string exe_dir = GLib.Path.get_dirname (exe_path);
                string resource_dir = GLib.Path.build_filename (exe_dir, "..", "data", "resources");

                if (has_preview_resources (resource_dir)) {
                    return resource_dir;
                }
            } catch (Error error) {
                warning ("resource dir fallback failed: %s", error.message);
            }

            return null;
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
  --text: #e6e9ef;
  --muted: #a9b0bf;
  --accent: #7aa2ff;
  --panel: #151922;
  --border: #2c3442;
  --code-bg: #171b22;
  --quote-bg: #141821;
}

@media (prefers-color-scheme: light) {
  :root {
    --bg: #f6f8fa;
    --text: #1f2328;
    --muted: #57606a;
    --accent: #0969da;
    --panel: #ffffff;
    --border: #d0d7de;
    --code-bg: #f6f8fa;
    --quote-bg: #f6f8fa;
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
  word-wrap: break-word;
}

.markdown-body p {
  margin: 0.75em 0;
}

.markdown-body img {
  max-width: 100%;
  height: auto;
}

.markdown-body a {
  color: var(--accent);
  text-decoration: none;
}

.markdown-body a:hover {
  text-decoration: underline;
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
  overflow: auto;
  padding: 16px 18px;
}

.markdown-body pre code {
  background: transparent;
  border: 0;
  padding: 0;
  white-space: pre;
}

.markdown-body pre.chroma {
  display: block;
}

.markdown-body pre.chroma code {
  background: transparent;
  border: 0;
  display: block;
  padding: 0;
  white-space: pre;
}

.markdown-body pre.chroma .line {
  display: block;
}

.markdown-body .chroma {
  color: var(--text);
}

.markdown-body .chroma .k,
.markdown-body .chroma .kd,
.markdown-body .chroma .kr,
.markdown-body .chroma .kt,
.markdown-body .chroma .kp {
  color: #7fbaf5;
}

.markdown-body .chroma .nf,
.markdown-body .chroma .nc,
.markdown-body .chroma .nt {
  color: #57c7ff;
}

.markdown-body .chroma .s,
.markdown-body .chroma .s1,
.markdown-body .chroma .s2,
.markdown-body .chroma .sa,
.markdown-body .chroma .sb,
.markdown-body .chroma .sc,
.markdown-body .chroma .sd,
.markdown-body .chroma .se,
.markdown-body .chroma .si,
.markdown-body .chroma .ss {
  color: #82cc6a;
}

.markdown-body .chroma .m,
.markdown-body .chroma .mi,
.markdown-body .chroma .mf,
.markdown-body .chroma .mh,
.markdown-body .chroma .mo {
  color: #56b6c2;
}

.markdown-body .chroma .c,
.markdown-body .chroma .ch,
.markdown-body .chroma .cm,
.markdown-body .chroma .c1,
.markdown-body .chroma .cs {
  color: #7f8caa;
  font-style: italic;
}

.markdown-body .chroma .p,
.markdown-body .chroma .o,
.markdown-body .chroma .ow {
  color: #c9d1d9;
}

.markdown-body .chroma .nb,
.markdown-body .chroma .na,
.markdown-body .chroma .no,
.markdown-body .chroma .nn,
.markdown-body .chroma .nv {
  color: #ecbe7b;
}

.markdown-body .chroma .err {
  color: #cf5967;
}

.markdown-body table {
  display: block;
  width: max-content;
  max-width: 100%;
  border-collapse: collapse;
  overflow: auto;
  margin: 1em 0;
}

.markdown-body td,
.markdown-body th {
  border: 1px solid var(--border);
  padding: 0.4em 0.7em;
}

.markdown-body th {
  font-weight: 600;
  background: var(--panel);
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

    }
}
