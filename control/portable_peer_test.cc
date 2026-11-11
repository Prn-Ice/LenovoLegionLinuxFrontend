#include "portable_peer.h"

namespace {
legion_control::PortableEndpoint Endpoint() {
  return {"unix:path=/run/legion-example/"
          "control.sock,guid=0123456789abcdef0123456789abcdef",
          "legion-bootstrap-probe-01234567-89ab-4cde-8fab-0123456789ab.service",
          123};
}

void test_endpoint_validation() {
  GError *error = nullptr;
  auto endpoint = Endpoint();
  g_assert_true(legion_control::ValidatePortableEndpoint(endpoint, &error));
  g_assert_no_error(error);
  for (const char *address :
       {"tcp:host=localhost,port=123", "unix:abstract=example",
        "unix:path=relative", "unix:path=/tmp/a;unix:path=/tmp/b",
        "unix:path=/tmp/a,guid=bad", "unix:path=/tmp/a,other=yes",
        "unix:path=/tmp/%00bad"}) {
    endpoint = Endpoint();
    endpoint.address = address;
    g_assert_false(legion_control::ValidatePortableEndpoint(endpoint, &error));
    g_assert_error(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT);
    g_clear_error(&error);
  }
  for (const char *unit : {"legion-control.service", "../bad.service",
                           "legion-bootstrap-probe-invalid.service"}) {
    endpoint = Endpoint();
    endpoint.unit = unit;
    g_assert_false(legion_control::ValidatePortableEndpoint(endpoint, &error));
    g_clear_error(&error);
  }
  endpoint = Endpoint();
  endpoint.helper_pid = 1;
  g_assert_false(legion_control::ValidatePortableEndpoint(endpoint, &error));
  g_clear_error(&error);
}

void test_cancelled_connect_never_uses_host_bus() {
  auto *cancel = g_cancellable_new();
  g_cancellable_cancel(cancel);
  GError *error = nullptr;
  auto *peer =
      legion_control::ConnectPortablePeerSync(Endpoint(), cancel, &error);
  g_assert_null(peer);
  g_assert_error(error, G_IO_ERROR, G_IO_ERROR_CANCELLED);
  g_clear_error(&error);
  g_object_unref(cancel);
}

void test_async_connect_rejects_invalid_endpoint() {
  auto endpoint = Endpoint();
  endpoint.address = "tcp:host=localhost,port=123";
  auto *cancel = g_cancellable_new();
  auto *loop = g_main_loop_new(nullptr, FALSE);
  bool completed = false;
  legion_control::ConnectPortablePeer(
      endpoint, cancel, [&](GDBusConnection *peer, GError *error) {
        g_assert_null(peer);
        g_assert_error(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT);
        g_clear_error(&error);
        completed = true;
        g_main_loop_quit(loop);
      });
  g_main_loop_run(loop);
  g_assert_true(completed);
  g_assert_false(g_cancellable_is_cancelled(cancel));
  g_object_unref(cancel);
  g_main_loop_unref(loop);
}
} // namespace

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/portable-peer/endpoint-validation",
                  test_endpoint_validation);
  g_test_add_func("/portable-peer/cancel-before-bus",
                  test_cancelled_connect_never_uses_host_bus);
  g_test_add_func("/portable-peer/async-invalid-endpoint",
                  test_async_connect_rejects_invalid_endpoint);
  return g_test_run();
}
