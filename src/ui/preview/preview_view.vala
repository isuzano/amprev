/*
 * SPDX-FileCopyrightText: 2026 Iuri Suzano <iuri@astware.bar>
 * SPDX-License-Identifier: MIT
 *
 * WebKit-backed preview pane.
 */

namespace Astware.Amprev {
    public class PreviewView : Gtk.Box {
        private const string scroll_world_name = "Astware.Amprev.Scroll";
        private WebKit.UserContentManager content_manager;
        private WebKit.WebView web_view;
        private string? pending_html = null;
        private double scroll_top = 0.0;
        private double scroll_height = 0.0;
        private double viewport_height = 0.0;
        private string last_html = "";
        private bool restore_scroll_pending = false;
        private double restore_fraction = 0.0;

        public signal void scroll_metrics_changed (double top, double height, double viewport);

        public PreviewView () {
            Object (
                orientation: Gtk.Orientation.VERTICAL,
                spacing: 0,
                hexpand: true,
                vexpand: true
            );

            web_view = new WebKit.WebView ();
            content_manager = web_view.get_user_content_manager ();
            content_manager.script_message_received.connect (on_script_message_received);
            content_manager.register_script_message_handler ("amprev_scroll", scroll_world_name);
            content_manager.add_script (new WebKit.UserScript.for_world (
                scroll_script (),
                WebKit.UserContentInjectedFrames.TOP_FRAME,
                WebKit.UserScriptInjectionTime.END,
                scroll_world_name,
                null,
                null
            ));
            web_view.context_menu.connect ((context_menu, hit_test_result) => {
                return true;
            });
            web_view.realize.connect (on_web_view_realized);
            web_view.load_changed.connect (on_load_changed);
            web_view.hexpand = true;
            web_view.vexpand = true;

            append (web_view);
        }

        public WebKit.WebView get_web_view () {
            return web_view;
        }

        public void load_html (string html) {
            if (html == last_html) {
                return;
            }

            pending_html = html;
            restore_scroll_pending = true;
            restore_fraction = current_fraction ();
            flush_pending_html ();
        }

        public void scroll_to_fraction (double fraction) {
            if (scroll_height <= viewport_height) {
                return;
            }

            double max_scroll = scroll_height - viewport_height;
            double clamped = fraction < 0.0 ? 0.0 : (fraction > 1.0 ? 1.0 : fraction);
            double target = clamped * max_scroll;

            var script = "window.scrollTo(0, " + ((int) target).to_string () + ");";
            web_view.evaluate_javascript.begin (
                script,
                -1,
                null,
                null,
                null,
                (obj, res) => {
                    try {
                        web_view.evaluate_javascript.end (res);
                    } catch (Error error) {
                        warning ("preview javascript evaluation failed: %s", error.message);
                    }
                }
            );
        }

        private void on_script_message_received (JSC.Value value) {
            string metrics = value.to_string ();
            parse_metrics (metrics);
        }

        private void parse_metrics (string metrics) {
            double new_top = scroll_top;
            double new_height = scroll_height;
            double new_viewport = viewport_height;

            foreach (string part in metrics.split (";")) {
                string[] key_value = part.split ("=", 2);
                if (key_value.length != 2) {
                    continue;
                }

                double parsed = 0.0;
                if (!double.try_parse (key_value[1], out parsed)) {
                    continue;
                }

                switch (key_value[0]) {
                case "top":
                    new_top = parsed;
                    break;
                case "height":
                    new_height = parsed;
                    break;
                case "viewport":
                    new_viewport = parsed;
                    break;
                default:
                    break;
                }
            }

            scroll_top = new_top;
            scroll_height = new_height;
            viewport_height = new_viewport;
            scroll_metrics_changed (scroll_top, scroll_height, viewport_height);
        }

        private void on_load_changed (WebKit.LoadEvent load_event) {
            if (load_event != WebKit.LoadEvent.FINISHED || !restore_scroll_pending) {
                return;
            }

            restore_scroll_pending = false;
            scroll_to_fraction (restore_fraction);
        }

        private void on_web_view_realized () {
            flush_pending_html ();
        }

        private void flush_pending_html () {
            if (pending_html == null || !web_view.get_realized ()) {
                return;
            }

            last_html = pending_html;
            web_view.load_html (pending_html, "about:blank");
            pending_html = null;
        }

        private double current_fraction () {
            double max_scroll = scroll_height - viewport_height;
            if (max_scroll <= 0.0) {
                return 0.0;
            }

            double fraction = scroll_top / max_scroll;
            return fraction < 0.0 ? 0.0 : (fraction > 1.0 ? 1.0 : fraction);
        }

        private string scroll_script () {
            return """
(function () {
  const handler = window.webkit && window.webkit.messageHandlers ? window.webkit.messageHandlers.amprev_scroll : null;
  if (!handler) {
    return;
  }

  let scheduled = false;

  function report () {
    scheduled = false;
    const root = document.documentElement;
    handler.postMessage(
      "top=" + Math.round(window.scrollY) +
      ";height=" + Math.round(root.scrollHeight) +
      ";viewport=" + Math.round(window.innerHeight)
    );
  }

  function queue_report () {
    if (scheduled) {
      return;
    }

    scheduled = true;
    window.requestAnimationFrame(report);
  }

  window.addEventListener("scroll", queue_report, { passive: true });
  window.addEventListener("resize", queue_report);
  window.addEventListener("load", queue_report);
  queue_report();
})();
""";
        }
    }
}
