// Exercise the actual channel codec without starting a Flutter engine.
#include "portable_control_channel.cc"
#include <vector>

namespace {
GDBusNodeInfo *protocol;

GVariant *Encode(const char *method, FlValue *values) {
  return Arguments(protocol->interfaces[0], method, values);
}

void test_typed_arguments() {
  g_autoptr(FlValue) values = fl_value_new_list();
  fl_value_append_take(values, fl_value_new_string("battery-conservation"));
  fl_value_append_take(values, fl_value_new_bool(TRUE));
  auto *encoded = Encode("SetToggle", values);
  g_assert_nonnull(encoded);
  g_assert_true(g_variant_is_of_type(encoded, G_VARIANT_TYPE("(sb)")));
  const char *name;
  gboolean enabled;
  g_variant_get(encoded, "(&sb)", &name, &enabled);
  g_assert_cmpstr(name, ==, "battery-conservation");
  g_assert_true(enabled);
  g_variant_unref(encoded);
  g_autoptr(FlValue) limits = fl_value_new_list();
  fl_value_append_take(limits, fl_value_new_int(40));
  fl_value_append_take(limits, fl_value_new_int(80));
  encoded = Encode("ApplyCustomConservation", limits);
  g_assert_nonnull(encoded);
  g_assert_true(g_variant_is_of_type(encoded, G_VARIANT_TYPE("(uu)")));
  g_variant_unref(encoded);
}

void test_rejects_unlisted_methods_and_types() {
  g_autoptr(FlValue) empty = fl_value_new_list();
  for (const char *method : {"RunCommand", "Authorize", "GetCapabilities",
                             "GetGraphicsBootRequest", "SetToggle"})
    g_assert_null(Encode(method, empty));
  auto *encoded = Encode("ApplyCurrentFanPreset", empty);
  g_assert_nonnull(encoded);
  g_variant_unref(encoded);
  g_autoptr(FlValue) values = fl_value_new_list();
  fl_value_append_take(values, fl_value_new_string("battery-conservation"));
  fl_value_append_take(values, fl_value_new_int(1));
  g_assert_null(Encode("SetToggle", values));
  g_autoptr(FlValue) negative = fl_value_new_list();
  fl_value_append_take(negative, fl_value_new_int(-1));
  fl_value_append_take(negative, fl_value_new_int(80));
  g_assert_null(Encode("ApplyCustomConservation", negative));
}

void test_payload_bounds() {
  std::vector<uint8_t> bytes(64 * 1024, 42);
  g_autoptr(FlValue) values = fl_value_new_list();
  fl_value_append_take(values,
                       fl_value_new_uint8_list(bytes.data(), bytes.size()));
  auto *encoded = Encode("ApplyFanCurve", values);
  g_assert_nonnull(encoded);
  g_assert_true(g_variant_is_of_type(encoded, G_VARIANT_TYPE("(ay)")));
  g_variant_unref(encoded);
  bytes.push_back(42);
  g_autoptr(FlValue) excessive = fl_value_new_list();
  fl_value_append_take(excessive,
                       fl_value_new_uint8_list(bytes.data(), bytes.size()));
  g_assert_null(Encode("ApplyFanCurve", excessive));
  g_autoptr(FlValue) untyped = fl_value_new_list();
  fl_value_append_take(untyped, fl_value_new_list());
  g_assert_null(Encode("ApplyFanCurve", untyped));
}

void test_session_close_cancels_once() {
  Session session;
  session.Close();
  session.Close();
  g_assert_true(session.closed);
  g_assert_true(g_cancellable_is_cancelled(session.cancel));
}
} // namespace

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, nullptr);
  protocol = g_dbus_node_info_new_for_xml(legion_control::control_xml, nullptr);
  g_test_add_func("/portable-channel/typed-arguments", test_typed_arguments);
  g_test_add_func("/portable-channel/reject-unlisted",
                  test_rejects_unlisted_methods_and_types);
  g_test_add_func("/portable-channel/payload-bounds", test_payload_bounds);
  g_test_add_func("/portable-channel/session-close",
                  test_session_close_cancels_once);
  const int result = g_test_run();
  g_dbus_node_info_unref(protocol);
  return result;
}
