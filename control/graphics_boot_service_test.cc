// Use real dispatch with the ordinary-user fixture runner; never start the root
// daemon or connect to the system bus. Authorization is faked on a private bus.
#define main legion_control_daemon_main
#include "legion_control_service.cc"
#undef main
#include "test_support/direct_command_runner.h"
#include <set>

namespace {
struct ControlledOperation final : legion_control::ManagedCommandOperation {
  bool cancelled = false;
  void Cancel() override { cancelled = true; }
};
struct ControlledRunner final : legion_control::ManagedCommandRunner {
  Completion completion;
  unsigned starts = 0;
  std::shared_ptr<ControlledOperation> operation;
  std::shared_ptr<legion_control::ManagedCommandOperation>
  Start(const std::string &, const std::vector<std::string> &, unsigned,
        Completion done) override {
    ++starts;
    completion = std::move(done);
    operation = std::make_shared<ControlledOperation>();
    return operation;
  }
  void Finish(legion_control::ManagedCommandStatus status,
              int exit_status = -1) {
    legion_control::ManagedCommandResult result;
    result.status = status;
    result.exit_status = exit_status;
    auto done = std::move(completion);
    done(std::move(result));
  }
};
struct Reply {
  GMainLoop *loop;
  GVariant *value = nullptr;
  GError *error = nullptr;
};

GVariant *request(GDBusConnection *client, GDBusConnection *server,
                  const char *method, GVariant *parameters, GError **error) {
  Reply reply{g_main_loop_new(nullptr, FALSE)};
  g_dbus_connection_call(
      client, g_dbus_connection_get_unique_name(server), path, iface, method,
      parameters, nullptr, G_DBUS_CALL_FLAGS_NONE, 5000, nullptr,
      [](GObject *source, GAsyncResult *result, gpointer data) {
        auto *reply = static_cast<Reply *>(data);
        reply->value = g_dbus_connection_call_finish(G_DBUS_CONNECTION(source),
                                                     result, &reply->error);
        g_main_loop_quit(reply->loop);
      },
      &reply);
  g_main_loop_run(reply.loop);
  g_main_loop_unref(reply.loop);
  *error = reply.error;
  return reply.value;
}

void test_boot_dispatch() {
  GTestDBus *test_bus = g_test_dbus_new(G_TEST_DBUS_NONE);
  g_test_dbus_up(test_bus);
  GError *error = nullptr;
  const auto flags = static_cast<GDBusConnectionFlags>(
      G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
      G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION);
  const char *address = g_test_dbus_get_bus_address(test_bus);
  GDBusConnection *server = g_dbus_connection_new_for_address_sync(
      address, flags, nullptr, nullptr, &error);
  g_assert_no_error(error);
  GDBusConnection *client = g_dbus_connection_new_for_address_sync(
      address, flags, nullptr, nullptr, &error);
  g_assert_no_error(error);
  Ctx context{};
  context.runner = legion_control::CreateDirectCommandRunner();
  context.info = g_dbus_node_info_new_for_xml(xml, &error);
  g_assert_no_error(error);
  guint registration = g_dbus_connection_register_object(
      server, path, context.info->interfaces[0], &vt, &context, nullptr,
      &error);
  g_assert_no_error(error);
  g_assert_cmpuint(registration, >, 0);

  auto check_capabilities = [&](const std::set<std::string> &expected) {
    GVariant *reply =
        request(client, server, "GetCapabilities", nullptr, &error);
    g_assert_no_error(error);
    g_assert_cmpstr(g_variant_get_type_string(reply), ==, "(uas)");
    guint32 version;
    GVariant *capabilities;
    g_variant_get(reply, "(u@as)", &version, &capabilities);
    g_assert_cmpuint(version, ==, 1);
    GVariantIter values;
    g_variant_iter_init(&values, capabilities);
    const char *value;
    std::set<std::string> actual;
    while (g_variant_iter_next(&values, "&s", &value))
      actual.emplace(value);
    g_assert_true(actual == expected);
    g_variant_unref(capabilities);
    g_variant_unref(reply);
  };
  check_capabilities({"interactive-control", "persistent-services"});

  GVariant *reply = request(client, server, "RequestGraphicsModeAtBoot",
                            g_variant_new("(s)", "hybrid-igpu-only"), &error);
  g_assert_null(reply);
  g_assert_nonnull(error);
  g_assert_nonnull(strstr(error->message, "Authorize must be called first"));
  g_clear_error(&error);
  context.auth[g_dbus_connection_get_unique_name(client)] = true;

  reply = request(client, server, "GetGraphicsBootRequest", nullptr, &error);
  g_assert_null(reply);
  g_assert_nonnull(error);
  g_assert_nonnull(strstr(error->message, "not enabled"));
  g_clear_error(&error);

  gchar *directory = g_dir_make_tmp("legion-boot-service-test-XXXXXX", &error);
  g_assert_no_error(error);
  const std::string helper = std::string(directory) + "/helper";
  const std::string log = std::string(directory) + "/calls";
  gchar *shell = g_find_program_in_path("sh");
  g_assert_nonnull(shell);
  const std::string script = std::string("#!") + shell +
                             "\nprintf '%s\\n' \"$*\" >> '" + log +
                             "'\nprintf '%s\\n' '{\"phase\":\"pending\"}'\n";
  g_free(shell);
  g_assert_true(
      g_file_set_contents(helper.c_str(), script.c_str(), -1, &error));
  g_assert_no_error(error);
  g_assert_cmpint(chmod(helper.c_str(), 0700), ==, 0);
  context.graphics_boot = helper;
  check_capabilities(
      {"interactive-control", "persistent-services", "next-boot-graphics"});
  context.mode = ControlConnectionMode::portable;
  check_capabilities({"interactive-control"});
  reply = request(client, server, "GetGraphicsBootRequest", nullptr, &error);
  g_assert_null(reply);
  g_assert_nonnull(error);
  g_assert_nonnull(strstr(error->message, "NotSupported"));
  g_clear_error(&error);
  context.mode = ControlConnectionMode::installed;

  reply = request(client, server, "RequestGraphicsModeAtBoot",
                  g_variant_new("(s)", "hybrid-auto"), &error);
  g_assert_null(reply);
  g_assert_nonnull(error);
  g_clear_error(&error);
  g_assert_false(g_file_test(log.c_str(), G_FILE_TEST_EXISTS));

  for (const auto &entry : std::vector<std::pair<const char *, const char *>>{
           {"RequestGraphicsModeAtBoot", "hybrid-igpu-only"},
           {"RequestGraphicsModeAtBoot", "hybrid"},
           {"GetGraphicsBootRequest", nullptr},
           {"CancelGraphicsModeAtBoot", nullptr}}) {
    reply = request(client, server, entry.first,
                    entry.second ? g_variant_new("(s)", entry.second) : nullptr,
                    &error);
    g_assert_no_error(error);
    g_assert_nonnull(reply);
    const gchar *output = nullptr;
    g_variant_get(reply, "(&s)", &output);
    g_assert_cmpstr(output, ==, "{\"phase\":\"pending\"}\n");
    g_variant_unref(reply);
    g_assert_null(context.active.get());
  }
  gchar *calls = nullptr;
  g_assert_true(g_file_get_contents(log.c_str(), &calls, nullptr, &error));
  g_assert_no_error(error);
  g_assert_cmpstr(calls, ==,
                  "request hybrid-igpu-only\nrequest hybrid\nstatus\ncancel\n");
  g_free(calls);

  // Exercise the actual desktop client, still on this private bus. Fake only
  // Polkit authorization; dispatch its subsequent request through production
  // code.
  g_dbus_connection_unregister_object(server, registration);
  struct ClientContext {
    Ctx *service;
    std::string authorized_sender;
    bool same_sender = false;
  } client_context{&context, "", false};
  const GDBusInterfaceVTable client_vt = {
      [](GDBusConnection *connection, const gchar *sender, const gchar *object,
         const gchar *interface, const gchar *method, GVariant *parameters,
         GDBusMethodInvocation *invocation, gpointer data) {
        auto *test = static_cast<ClientContext *>(data);
        if (g_str_equal(method, "Authorize")) {
          test->authorized_sender = sender;
          test->service->auth[sender] = true;
          done(invocation);
        } else {
          test->same_sender = test->authorized_sender == sender;
          call(connection, sender, object, interface, method, parameters,
               invocation, test->service);
        }
      },
      nullptr,
      nullptr,
      {nullptr}};
  registration = g_dbus_connection_register_object(
      server, path, context.info->interfaces[0], &client_vt, &client_context,
      nullptr, &error);
  g_assert_no_error(error);
  reply = g_dbus_connection_call_sync(
      server, "org.freedesktop.DBus", "/org/freedesktop/DBus",
      "org.freedesktop.DBus", "RequestName", g_variant_new("(su)", bus, 0u),
      G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, 5000, nullptr, &error);
  g_assert_no_error(error);
  g_assert_nonnull(reply);
  g_variant_unref(reply);
  GSubprocessLauncher *launcher =
      g_subprocess_launcher_new(static_cast<GSubprocessFlags>(
          G_SUBPROCESS_FLAGS_STDOUT_PIPE | G_SUBPROCESS_FLAGS_STDERR_MERGE));
  g_subprocess_launcher_setenv(launcher, "DBUS_SYSTEM_BUS_ADDRESS", address,
                               TRUE);
  GSubprocess *process = g_subprocess_launcher_spawn(
      launcher, &error, GRAPHICS_CLIENT_PATH, "hybrid-igpu-only", nullptr);
  g_assert_no_error(error);
  g_object_unref(launcher);
  GMainLoop *loop = g_main_loop_new(nullptr, FALSE);
  g_subprocess_communicate_utf8_async(
      process, nullptr, nullptr,
      [](GObject *source, GAsyncResult *result, gpointer data) {
        GError *error = nullptr;
        gchar *output = nullptr;
        g_assert_true(g_subprocess_communicate_utf8_finish(
            G_SUBPROCESS(source), result, &output, nullptr, &error));
        g_assert_no_error(error);
        g_assert_true(g_subprocess_get_successful(G_SUBPROCESS(source)));
        g_assert_nonnull(strstr(output, "Nothing changed now"));
        g_free(output);
        g_main_loop_quit(static_cast<GMainLoop *>(data));
      },
      loop);
  g_main_loop_run(loop);
  g_main_loop_unref(loop);
  g_object_unref(process);
  g_assert_true(client_context.same_sender);

  // Keep real dispatch, but control cleanup completion to exercise Busy and
  // the permanent no-further-writes latch independently of process timing.
  auto controlled = std::make_shared<ControlledRunner>();
  context.runner = controlled;
  context.cli = helper;
  auto begin_graphics = [&](Reply *pending_reply) {
    g_dbus_connection_call(
        client, g_dbus_connection_get_unique_name(server), path, iface,
        "SetGraphicsMode", g_variant_new("(s)", "hybrid"), nullptr,
        G_DBUS_CALL_FLAGS_NONE, 5000, nullptr,
        [](GObject *source, GAsyncResult *result, gpointer data) {
          auto *reply = static_cast<Reply *>(data);
          reply->value = g_dbus_connection_call_finish(
              G_DBUS_CONNECTION(source), result, &reply->error);
          g_main_loop_quit(reply->loop);
        },
        pending_reply);
    bool expired = false;
    const guint timeout = g_timeout_add(
        5000,
        [](gpointer data) -> gboolean {
          *static_cast<bool *>(data) = true;
          return G_SOURCE_REMOVE;
        },
        &expired);
    while (!context.active && !expired)
      g_main_context_iteration(nullptr, TRUE);
    if (!expired)
      g_source_remove(timeout);
    g_assert_false(expired);
  };
  for (int status : {2, 3}) {
    Reply pending_reply{g_main_loop_new(nullptr, FALSE)};
    begin_graphics(&pending_reply);
    controlled->Finish(legion_control::ManagedCommandStatus::commandFailed,
                       status);
    g_main_loop_run(pending_reply.loop);
    g_assert_null(pending_reply.value);
    g_assert_nonnull(pending_reply.error);
    g_assert_nonnull(
        strstr(pending_reply.error->message,
               status == 2 ? "GraphicsBlocked" : "GraphicsPending"));
    g_clear_error(&pending_reply.error);
    g_main_loop_unref(pending_reply.loop);
  }
  Reply pending_reply{g_main_loop_new(nullptr, FALSE)};
  begin_graphics(&pending_reply);
  context.active->command->Cancel();
  g_assert_true(controlled->operation->cancelled);
  reply = request(client, server, "GetGraphicsBootRequest", nullptr, &error);
  g_assert_null(reply);
  g_assert_nonnull(error);
  g_assert_nonnull(strstr(error->message, "Busy"));
  g_clear_error(&error);
  g_assert_nonnull(context.active.get());
  controlled->Finish(legion_control::ManagedCommandStatus::cleanupFailed);
  g_main_loop_run(pending_reply.loop);
  g_assert_null(pending_reply.value);
  g_assert_nonnull(pending_reply.error);
  g_assert_nonnull(strstr(pending_reply.error->message, "Unavailable"));
  g_clear_error(&pending_reply.error);
  g_main_loop_unref(pending_reply.loop);
  g_assert_null(context.active.get());
  g_assert_true(context.cleanup_failed);
  reply = request(client, server, "GetGraphicsBootRequest", nullptr, &error);
  g_assert_null(reply);
  g_assert_nonnull(error);
  g_assert_nonnull(strstr(error->message, "Unavailable"));
  g_clear_error(&error);
  g_assert_cmpuint(controlled->starts, ==, 3);

  unlink(log.c_str());
  unlink(helper.c_str());
  rmdir(directory);
  g_free(directory);

  g_dbus_connection_unregister_object(server, registration);
  g_dbus_node_info_unref(context.info);
  g_dbus_connection_close_sync(client, nullptr, nullptr);
  g_dbus_connection_close_sync(server, nullptr, nullptr);
  g_object_unref(client);
  g_object_unref(server);
  g_test_dbus_down(test_bus);
  g_object_unref(test_bus);
}
} // namespace

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/control/next-boot-dispatch", test_boot_dispatch);
  return g_test_run();
}
