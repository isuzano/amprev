project(
    'amprev',
    'vala',
    version: '0.1.0',
    meson_version: '>=1.0.0',
    default_options: [
        'buildtype=debugoptimized',
        'warning_level=2',
    ],
)

gnome = import('gnome')
app_id = 'bar.astware.amprev'
app_name = 'Amprev'

dependency_gtk4 = dependency('gtk4')
dependency_adw = dependency('libadwaita-1')
dependency_webkit = dependency('webkitgtk-6.0')
dependency_gio = dependency('gio-2.0')
dependency_glib = dependency('glib-2.0')

subdir('data')
subdir('src')
