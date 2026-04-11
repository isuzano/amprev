install_data(
    'resources/style.css',
    install_dir: join_paths(get_option('datadir'), 'amprev', 'resources'),
)

install_data(
    'amprev.png',
    install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', '128x128', 'apps'),
)

custom_target(
    'amprev-icon-theme',
    input: 'amprev.png',
    output: 'amprev-icon-theme.stamp',
    command: [
        'sh',
        '-c',
        'mkdir -p "$1/icons/hicolor/128x128/apps" && cp "$0" "$1/icons/hicolor/128x128/apps/amprev.png" && touch "$2"',
        '@INPUT@',
        '@OUTDIR@',
        '@OUTPUT@',
    ],
    build_by_default: true,
)

install_data(
    'bar.astware.amprev.gschema.xml',
    install_dir: join_paths(get_option('datadir'), 'glib-2.0', 'schemas'),
)

configure_file(
    input: 'bar.astware.amprev.gschema.xml',
    output: 'bar.astware.amprev.gschema.xml',
    copy: true,
)

desktop_conf = configuration_data()
desktop_conf.set('APP_ID', app_id)
desktop_conf.set('APP_NAME', app_name)
desktop_conf.set('APP_EXEC', meson.project_name())
desktop_conf.set('APP_ICON', 'amprev')

configure_file(
    input: 'amprev.desktop.in',
    output: 'amprev.desktop',
    configuration: desktop_conf,
    install: true,
    install_dir: join_paths(get_option('datadir'), 'applications'),
)

metainfo_conf = configuration_data()
metainfo_conf.set('APP_ID', app_id)
metainfo_conf.set('APP_NAME', app_name)
metainfo_conf.set('VERSION', meson.project_version())

configure_file(
    input: 'amprev.metainfo.xml.in',
    output: 'amprev.metainfo.xml',
    configuration: metainfo_conf,
    install: true,
    install_dir: join_paths(get_option('datadir'), 'metainfo'),
)
