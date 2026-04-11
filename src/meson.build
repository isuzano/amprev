config = configuration_data()
config.set('APP_DATA_DIR', join_paths(get_option('prefix'), get_option('datadir'), meson.project_name(), 'resources'))

config_vala = configure_file(
    input: 'config.vala.in',
    output: 'config.vala',
    configuration: config,
)

sources = files(
    'main.vala',
    'app/application.vala',
    'app/actions.vala',
    'ui/main_window.vala',
    'ui/editor/editor_view.vala',
    'ui/preview/preview_view.vala',
    'core/markdown_engine.vala',
    'services/editor_highlight_service.vala',
    'services/export_service.vala',
    'services/theme_service.vala',
    'services/sync_service.vala',
    'models/document.vala',
) + [config_vala]

executable(
    'amprev',
    sources,
    dependencies: [
        dependency_gtk4,
        dependency_adw,
        dependency_webkit,
        dependency_gio,
        dependency_glib,
    ],
    vala_args: [
        '--target-glib=2.50',
    ],
    c_args: [
        # Generated Vala C hits benign warnings in the glue layer; keep the build readable.
        '-Wno-unused-parameter',
        '-Wno-unused-variable',
        '-Wno-unused-but-set-variable',
        '-Wno-unused-function',
        '-Wno-discarded-qualifiers',
        '-Wno-pointer-to-int-cast',
        '-Wno-cast-function-type',
    ],
    install: true,
)
