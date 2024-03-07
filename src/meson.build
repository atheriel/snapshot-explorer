snapshot_explorer_sources = [
  'dbus.vala',
  'fs.vala',
  'main.vala',
  'window.vala',
  'zfs.vala',
]

snapshot_explorer_deps = [
  dependency('gio-2.0', version: '>= 2.50'),
  dependency('gtk4', version: '>= 4.0'),
  dependency('libadwaita-1'),
]

gnome = import('gnome')
snapshot_explorer_sources += gnome.compile_resources(
  'snapshot_explorer-resources',
  'snapshot_explorer.gresource.xml',
  c_name: 'snapshot_explorer'
)

executable(
  'snapshot-explorer', snapshot_explorer_sources,
  vala_args: '--target-glib=2.50',
  dependencies: snapshot_explorer_deps,
  install: true,
)
