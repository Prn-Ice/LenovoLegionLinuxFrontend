/// Removes bundled loader and module paths before starting host commands.
Map<String, String> hostCommandEnvironment(Map<String, String> source) {
  return Map.unmodifiable({
    for (final entry in source.entries)
      if (!entry.key.startsWith('LD_') &&
          !entry.key.startsWith('GIO_') &&
          !const {
            'GCONV_PATH',
            'GI_TYPELIB_PATH',
            'PYTHONPATH',
            'PYTHONHOME',
            'DBUS_SYSTEM_BUS_ADDRESS',
            'APPDIR',
            'APPIMAGE',
            'ARGV0',
            'GTK_PATH',
            'GTK_EXE_PREFIX',
            'GTK_DATA_PREFIX',
            'GTK_MODULES',
            'GTK3_MODULES',
            'GDK_PIXBUF_MODULE_FILE',
            'GDK_PIXBUF_MODULEDIR',
            'GSETTINGS_SCHEMA_DIR',
            'GSETTINGS_BACKEND',
            'FONTCONFIG_FILE',
            'FONTCONFIG_PATH',
            'XDG_DATA_DIRS',
            'PATH',
          }.contains(entry.key))
        entry.key: entry.value,
    'PATH': '/run/current-system/sw/bin:/usr/sbin:/usr/bin:/sbin:/bin',
  });
}
