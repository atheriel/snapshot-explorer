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

appstream_util = find_program('appstream-util', required: false)
if appstream_util.found()
  test('Validate appstream file', appstream_util,
    args: ['validate', appstream_file]
  )
endif

install_data('org.github.atheriel.snapshot-explorer.gschema.xml',
  install_dir: join_paths(get_option('datadir'), 'glib-2.0/schemas')
)

compile_schemas = find_program('glib-compile-schemas', required: false)
if compile_schemas.found()
  test('Validate schema file', compile_schemas,
    args: ['--strict', '--dry-run', meson.current_source_dir()]
  )
endif

subdir('icons')
