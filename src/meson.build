snapshot_explorer_sources = [
  'config.vapi',
  'dbus.vala',
  'fs.vala',
  'main.vala',
  'snapshot-pane.vala',
  'snapshot-row.vala',
  'window.vala',
  'zfs.vala',
]

adwaita_dep = dependency('libadwaita-1', version: '>=1.5')

snapshot_explorer_deps = [
  config_dep,
  dependency('gio-2.0', version: '>= 2.50'),
  dependency('gtk4', version: '>= 4.10'),
  adwaita_dep
]

if adwaita_dep.version().version_compare('>=1.6')
  add_project_arguments(
    ['-D', 'ADW_HAS_SPINNER'], language: 'vala'
  )
endif

gnome = import('gnome')
snapshot_explorer_sources += gnome.compile_resources(
  'snapshot_explorer-resources',
  'snapshot_explorer.gresource.xml',
  c_name: 'snapshot_explorer'
)

executable(
  'snapshot-explorer', snapshot_explorer_sources,
  vala_args: '--target-glib=2.50',
  c_args: [
    # Artifacts of Vala's code generation.
    '-Wno-unused-but-set-variable',
    '-Wno-unused-function',
    '-Wno-unused-parameter',
    '-Wno-unused-variable',
    # See: https://gitlab.gnome.org/GNOME/vala/-/issues/1413
    '-Wno-incompatible-function-pointer-types',
    '-Wno-cast-function-type-mismatch',
  ],
  dependencies: snapshot_explorer_deps,
  install: true,
)
