project('snapshot-explorer', ['c', 'vala'],
  version: '0.1.0',
  meson_version: '>= 0.50.0',
  default_options: [
    'warning_level=2',
  ],
)

add_project_arguments('--enable-experimental-non-null', language: 'vala')

if get_option('flatpak')
  add_project_arguments('-D', 'FLATPAK', language: 'vala')
endif

i18n = import('i18n')

subdir('data')
subdir('src')
subdir('po')

meson.add_install_script('build-aux/meson/postinstall.py')
