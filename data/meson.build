desktop_file_in = configure_file(
  input: ('@0@.desktop.in.in').format(application_id),
  output: ('@0@.desktop.in').format(application_id),
  configuration: data_conf
)

desktop_file = i18n.merge_file(
  input: desktop_file_in,
  output: ('@0@.desktop').format(application_id),
  type: 'desktop',
  po_dir: '../po',
  install: true,
  install_dir: join_paths(get_option('datadir'), 'applications')
)

desktop_utils = find_program('desktop-file-validate', required: false)
if desktop_utils.found()
  test('Validate desktop file', desktop_utils,
    args: [desktop_file]
  )
endif

metainfo_file = configure_file(
  input: ('@0@.metainfo.xml.in.in').format(application_id),
  output: ('@0@.metainfo.xml.in').format(application_id),
  configuration: data_conf
)

appstream_file = i18n.merge_file(
  input: metainfo_file,
  output: ('@0@.metainfo.xml').format(application_id),
  po_dir: '../po',
  install: true,
  install_dir: join_paths(get_option('datadir'), 'metainfo')
)

appstream_cli = find_program('appstreamcli', required: false)
if appstream_cli.found()
  test('Validate appstream file', appstream_cli,
    args: ['validate', '--no-net', appstream_file]
  )
endif

gschema_file = configure_file(
  input: ('@0@.gschema.xml.in').format(application_id),
  output: ('@0@.gschema.xml').format(application_id),
  configuration: data_conf,
  install: true,
  install_dir: join_paths(get_option('datadir'), 'glib-2.0/schemas')
)

compile_schemas = find_program('glib-compile-schemas', required: false)
if compile_schemas.found()
  test('Validate schema file', compile_schemas,
    args: ['--strict', '--dry-run', meson.current_build_dir()]
  )
endif

subdir('icons')
