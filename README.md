<div align="center">

# amprev

## Minimal, fast and disciplined Markdown previewer built with Vala, GTK4 and Libadwaita.

![language](https://img.shields.io/badge/language-Vala-blue?logo=gnome)
![stack](https://img.shields.io/badge/stack-GTK4%20%2B%20Libadwaita-purple)
![build](https://img.shields.io/badge/build-Meson-grey)
![architecture](https://img.shields.io/badge/architecture-clean-informational)
![status](https://img.shields.io/badge/status-active-brightgreen)
![philosophy](https://img.shields.io/badge/discipline-ASTEAM-black)
![license](https://img.shields.io/badge/license-MIT-green)

</div>

---

**amprev** is a lightweight Markdown preview application focused on:

* predictable behavior
* clean UI
* fast feedback loop while writing
* engineering discipline over feature bloat

It follows the ASTEAM philosophy:
**clear boundaries, minimal abstractions and intentional design decisions.**

---

## Features

* Live Markdown preview
* Clean and neutral UI (Libadwaita)
* Dark / Light / System theme support
* Export to PDF
* Scroll synchronization (proportional)
* Syntax highlight support
* Keyboard-driven workflow
* Minimal and distraction-free interface

---

## Design Philosophy

amprev is not trying to be everything.

It intentionally avoids:

* complex WYSIWYG behavior
* heavy plugin systems
* unnecessary abstractions

Core principles:

* **Editor is the source of truth**
* Preview is always derived and disposable
* UI should not own business logic
* Rendering must be predictable and cheap
* Simplicity over cleverness

---

## Architecture

The project is organized around clear boundaries:

* `models/` → document state and persistence rules
* `core/` → markdown engine (UI-agnostic)
* `services/` → theme, sync, export, highlight
* `ui/` → window and visual composition
* `app/` → bootstrap and actions

Each module has a single responsibility and avoids cross-layer leakage.

---

## Theming

amprev supports:

* `system` → follows OS theme via Libadwaita
* `dark` → forced dark mode
* `light` → forced light mode

The stored preference represents user intent, not final toolkit state.

---

## Scroll Sync

Scroll synchronization is **proportional**, not semantic.

This is a deliberate trade-off:

* ✔ fast and stable
* ✔ low complexity
* ✖ not pixel-perfect for all structures

---

## Export

PDF export is supported.

Notes:

* output fidelity depends on the rendering backend
* export does not mutate editor state
* failures are handled without crashing the app

---

## Build

### Requirements

* Vala
* Meson
* Ninja
* GTK4
* Libadwaita

### Compile

```bash
meson setup build
meson compile -C build
```

### Run

```bash
./build/amprev
```

---

## Project Status

Active development.

Focus areas:

* stability
* rendering performance
* UI consistency
* clean architecture

---

## Commenting Policy

amprev follows ASTEAM-style comments:

* document **intent**, not syntax
* document **contracts and limits**
* avoid noise and redundancy

If the code is clear, it stays uncommented.

---

## Contributing

Contributions are welcome, but discipline matters.

Before contributing:

* respect project structure
* avoid unnecessary abstractions
* keep changes small and focused
* follow ASTEAM commenting style

---

## License

MIT

---

## Final Note

This project is built with a simple rule:

> If it needs a comment to explain obvious code, the code is wrong.
> If it needs a comment to explain a decision, the comment is mandatory.
