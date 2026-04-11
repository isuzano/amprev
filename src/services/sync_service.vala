/*
 * SPDX-FileCopyrightText: 2026 Iuri Suzano <iuri@astware.bar>
 * SPDX-License-Identifier: MIT
 *
 * Proportional scroll synchronizer between editor and preview.
 */

namespace Astware.Amprev {
    /* Maps editor and preview positions proportionally.
     * This is intentional approximation, not semantic block alignment.
     */
    public class SyncService : Object {
        private bool enabled_state = true;
        private bool suppress_editor_event = false;
        private bool suppress_preview_event = false;
        private EditorView? editor_view;
        private PreviewView? preview_view;

        public bool enabled {
            get { return enabled_state; }
        }

        public void bind (EditorView editor_view, PreviewView preview_view) {
            this.editor_view = editor_view;
            this.preview_view = preview_view;

            editor_view.get_vadjustment ().value_changed.connect (() => {
                on_editor_scrolled ();
            });

            preview_view.scroll_metrics_changed.connect ((top, height, viewport) => {
                on_preview_scrolled (top, height, viewport);
            });
        }

        public void set_enabled (bool enabled) {
            enabled_state = enabled;
        }

        private void on_editor_scrolled () {
            if (!enabled_state || preview_view == null || editor_view == null) {
                return;
            }

            if (suppress_preview_event) {
                suppress_preview_event = false;
                return;
            }

            double fraction = editor_view.get_scroll_fraction ();
            suppress_editor_event = true;
            preview_view.scroll_to_fraction (fraction);
        }

        private void on_preview_scrolled (double top, double height, double viewport) {
            if (!enabled_state || editor_view == null) {
                return;
            }

            if (suppress_editor_event) {
                suppress_editor_event = false;
                return;
            }

            double max_scroll = (height - viewport) > 1.0 ? (height - viewport) : 1.0;
            double fraction = top / max_scroll;
            fraction = fraction < 0.0 ? 0.0 : (fraction > 1.0 ? 1.0 : fraction);
            suppress_preview_event = true;
            editor_view.scroll_to_fraction (fraction);
        }
    }
}
