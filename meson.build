project('snapshot-explorer', ['c', 'vala'],
  version: '0.1.0',
  meson_version: '>= 0.51.0',
  default_options: [
    'warning_level=2',
  ],
)

application_id = 'org.github.atheriel.snapshot-explorer'

vapi_dir = meson.current_source_dir() / 'vapi'
add_project_arguments(['--vapidir', vapi_dir, '--enable-experimental-non-null'],
                      language: 'vala')

if get_option('flatpak')
  add_project_arguments('-D', 'FLATPAK', language: 'vala')
endif

i18n = import('i18n')
add_project_arguments(
  '-DGETTEXT_PACKAGE="@0@"'.format(meson.project_name()), language: 'c'
)

conf = configuration_data()
conf.set_quoted('APP_ID', application_id)
conf.set_quoted('VERSION', meson.project_version())
conf.set_quoted('GETTEXT_PACKAGE', meson.project_name())
conf.set_quoted('LOCALEDIR', get_option('prefix') / get_option('localedir'))
config_h = configure_file(output: 'config.h', configuration: conf)
config_dep = declare_dependency(
  sources: config_h, include_directories: include_directories('.')
)

subdir('data')
subdir('src')
subdir('po')

if get_option('enable-nautilus-extension') and get_option('flatpak')
  warning('The Nautilus extension cannot run under Flatpak, skipping.')
elif get_option('enable-nautilus-extension')
  subdir('nautilus')
endif

meson.add_install_script('build-aux/meson/postinstall.py')
