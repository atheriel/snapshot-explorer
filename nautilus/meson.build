extension_sources = [
  'shim.c',
  'extension.vala',
  '../vapi/nautilus.vapi',
]

# Use the pkg-config dependency for libnautilus-extension so we can find the
# correct installation and include paths for extensions. Unfortunately, this
# dependency can't be passed to a Vala shared_module() target directly, because
# it is missing a VAPI -- we provide our own.
#
# Instead we use find_library() for the C compiler directly, the workaround
# suggested by Meson's docs at time of writing.

extension_dep = dependency('libnautilus-extension', version: '>= 3.0.0')
extension_dir = extension_dep.get_pkgconfig_variable('extensiondir')
include_dir = extension_dep.get_pkgconfig_variable('includedir') + '/nautilus'

extension_deps = [
  dependency('gtk+-3.0', version: '>= 3.22'),
  meson.get_compiler('c').find_library('libnautilus-extension'),
]

shared_module(
  'snapshot-extension', extension_sources,
  dependencies: extension_deps,
  vala_args: '--target-glib=2.50',
  c_args: '-I' + include_dir,
  install: true,
  install_dir: [extension_dir, false, false]
)
