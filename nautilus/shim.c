#include <glib-object.h>

/* Vala's C bindings are not currently able to handle the type signature require
   for Nautilus extension modules, so we discard the const modifier in this shim
   C code. */

void _nautilus_module_list_types(GType **types, int *num_types);

void nautilus_module_list_types(const GType **types, int *num_types)
{
  _nautilus_module_list_types((GType **) types, num_types);
}
