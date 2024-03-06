extension_sources = [
  'extension.vala',
  'shim.c',
  'zfs.vala',
]

extension_dep = dependency('libnautilus-extension', version: '>= 3.0.0')
extension_deps = [
  extension_dep,
  dependency('gtk+-3.0', version: '>= 3.22'),
]

extension_dir = extension_dep.get_variable(pkgconfig: 'extensiondir')

shared_module(
  'snapshot-extension', extension_sources,
  dependencies: extension_deps,
  vala_args: '--target-glib=2.50',
  install: true,
  install_dir: [extension_dir, false, false]
)
