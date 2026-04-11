/*
 * SPDX-FileCopyrightText: 2026 Iuri Suzano <iuri@astware.bar>
 * SPDX-License-Identifier: MIT
 *
 * Markdown editor pane.
 */

namespace Astware.Amprev {
    public class EditorView : Gtk.Box {
        private Gtk.ScrolledWindow scrolled_window;
        private Gtk.TextView line_view;
        private Gtk.TextView text_view;
        private Gtk.TextBuffer line_buffer;
        private uint update_lines_id = 0;

        public EditorView () {
            Object (
                orientation: Gtk.Orientation.VERTICAL,
                spacing: 0,
                hexpand: true,
                vexpand: true
            );

            scrolled_window = new Gtk.ScrolledWindow ();
            scrolled_window.hexpand = true;
            scrolled_window.vexpand = true;
            scrolled_window.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);

            var content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            content.hexpand = true;
            content.vexpand = true;

            line_view = new Gtk.TextView ();
            line_view.editable = false;
            line_view.cursor_visible = false;
            line_view.monospace = true;
            line_view.wrap_mode = Gtk.WrapMode.NONE;
            line_view.left_margin = 12;
            line_view.right_margin = 12;
            line_view.top_margin = 18;
            line_view.bottom_margin = 18;
            line_view.hexpand = false;
            line_view.vexpand = true;
            line_view.width_request = 48;
            line_view.add_css_class ("line-numbers");
            line_buffer = line_view.buffer;

            text_view = new Gtk.TextView ();
            text_view.monospace = true;
            text_view.wrap_mode = Gtk.WrapMode.NONE;
            text_view.left_margin = 18;
            text_view.right_margin = 18;
            text_view.top_margin = 18;
            text_view.bottom_margin = 18;
            text_view.hexpand = true;
            text_view.vexpand = true;

            content.append (line_view);
            content.append (text_view);
            scrolled_window.set_child (content);
            append (scrolled_window);

            get_buffer ().changed.connect (() => {
                queue_update_line_numbers ();
            });
            queue_update_line_numbers ();
        }

        public Gtk.TextBuffer get_buffer () {
            return text_view.buffer;
        }

        public Gtk.Adjustment get_vadjustment () {
            return scrolled_window.get_vadjustment ();
        }

        public string get_markdown () {
            Gtk.TextIter start;
            Gtk.TextIter end;
            var buffer = get_buffer ();
            buffer.get_bounds (out start, out end);
            return buffer.get_text (start, end, true);
        }

        public void set_markdown (string markdown) {
            get_buffer ().set_text (markdown, -1);
            queue_update_line_numbers ();
        }

        public double get_scroll_fraction () {
            var adjustment = get_vadjustment ();
            double max = adjustment.upper - adjustment.page_size;
            if (max <= 0.0) {
                return 0.0;
            }

            double fraction = adjustment.value / max;
            return fraction < 0.0 ? 0.0 : (fraction > 1.0 ? 1.0 : fraction);
        }

        public void scroll_to_fraction (double fraction) {
            var adjustment = get_vadjustment ();
            double max = adjustment.upper - adjustment.page_size;
            if (max <= 0.0) {
                return;
            }

            double clamped = fraction < 0.0 ? 0.0 : (fraction > 1.0 ? 1.0 : fraction);
            adjustment.value = clamped * max;
        }

        private void queue_update_line_numbers () {
            if (update_lines_id != 0) {
                GLib.Source.remove (update_lines_id);
                update_lines_id = 0;
            }

            update_lines_id = GLib.Idle.add (() => {
                update_lines_id = 0;
                update_line_numbers ();
                return false;
            });
        }

        private void update_line_numbers () {
            var buffer = get_buffer ();
            int line_count = buffer.get_line_count ();
            if (line_count < 1) {
                line_count = 1;
            }

            var numbers = new StringBuilder ();
            for (int i = 1; i <= line_count; i++) {
                numbers.append_printf ("%d", i);
                if (i < line_count) {
                    numbers.append_c ('\n');
                }
            }

            line_buffer.set_text (numbers.str, -1);
        }
    }
}
