#include "portable_control_channel.h"

#include "control_protocol.h"
#include "portable_peer.h"
#include "trusted_executable.h"

#include <climits>
#include <cstring>
#include <memory>
#include <string>

namespace {
struct Session {
  std::string id;
  GDBusConnection *peer = nullptr;
  GCancellable *cancel = g_cancellable_new();
  bool closed = false;
  void Close() {
    if (closed)
      return;
    closed = true;
    g_cancellable_cancel(cancel);
    if (peer && !g_dbus_connection_is_closed(peer))
      g_dbus_connection_close(peer, nullptr, nullptr, nullptr);
  }
  ~Session() {
    Close();
    g_clear_object(&peer);
    g_object_unref(cancel);
  }
};

struct Host {
  FlMethodChannel *channel = nullptr;
  GDBusNodeInfo *protocol =
      g_dbus_node_info_new_for_xml(legion_control::control_xml, nullptr);
  std::shared_ptr<Session> session;
  ~Host() {
    if (session)
      session->Close();
    g_dbus_node_info_unref(protocol);
    g_object_unref(channel);
  }
};

FlValue *Field(FlValue *map, const char *name, FlValueType type) {
  if (!map || fl_value_get_type(map) != FL_VALUE_TYPE_MAP)
    return nullptr;
  auto *value = fl_value_lookup_string(map, name);
  return value && fl_value_get_type(value) == type ? value : nullptr;
}

void Error(FlMethodCall *call, const char *code, const char *message) {
  fl_method_call_respond_error(call, code, message, nullptr, nullptr);
}

void ConnectionError(FlMethodCall *call, GError *error, bool connecting) {
  char *remote = error ? g_dbus_error_get_remote_error(error) : nullptr;
  const char *code = remote ? remote : (connecting ? "setup" : "unavailable");
  if (!remote && g_error_matches(error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
    code = "cancelled";
  else if (!remote && g_error_matches(error, G_IO_ERROR, G_IO_ERROR_TIMED_OUT))
    code = "timeout";
  Error(call, code, error ? error->message : "Control connection failed.");
  g_free(remote);
  g_clear_error(&error);
}

GVariant *Arguments(GDBusInterfaceInfo *protocol, const char *method,
                    FlValue *values) {
  auto *info = g_dbus_interface_info_lookup_method(protocol, method);
  if (!info || g_str_equal(method, "Authorize") ||
      g_str_equal(method, "GetCapabilities") ||
      (info->out_args && info->out_args[0]))
    return nullptr;
  size_t expected = 0;
  while (info->in_args && info->in_args[expected])
    ++expected;
  if (fl_value_get_length(values) != expected)
    return nullptr;
  GVariantBuilder arguments;
  g_variant_builder_init(&arguments, G_VARIANT_TYPE_TUPLE);
  bool valid = true;
  for (size_t index = 0; index < expected && valid; ++index) {
    auto *value = fl_value_get_list_value(values, index);
    const char *signature = info->in_args[index]->signature;
    const auto type = fl_value_get_type(value);
    if (!strcmp(signature, "s") && type == FL_VALUE_TYPE_STRING &&
        strlen(fl_value_get_string(value)) <= 128)
      g_variant_builder_add(&arguments, "s", fl_value_get_string(value));
    else if (!strcmp(signature, "b") && type == FL_VALUE_TYPE_BOOL)
      g_variant_builder_add(&arguments, "b", fl_value_get_bool(value));
    else if (!strcmp(signature, "u") && type == FL_VALUE_TYPE_INT &&
             fl_value_get_int(value) >= 0 &&
             fl_value_get_int(value) <= UINT_MAX)
      g_variant_builder_add(&arguments, "u", guint32(fl_value_get_int(value)));
    else if (!strcmp(signature, "ay") && type == FL_VALUE_TYPE_UINT8_LIST &&
             fl_value_get_length(value) <= (g_str_equal(method, "ApplyFanCurve")
                                                ? 64 * 1024
                                                : 16 * 1024 * 1024))
      g_variant_builder_add_value(
          &arguments, g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE,
                                                fl_value_get_uint8_list(value),
                                                fl_value_get_length(value), 1));
    else
      valid = false;
  }
  if (!valid) {
    g_variant_builder_clear(&arguments);
    return nullptr;
  }
  return g_variant_ref_sink(g_variant_builder_end(&arguments));
}

struct Invocation {
  std::shared_ptr<Session> session;
  FlMethodCall *call;
  bool metadata;
  ~Invocation() { g_object_unref(call); }
};

void Invoke(const std::shared_ptr<Session> &session, FlMethodCall *call,
            const char *method, GVariant *arguments, bool metadata = false) {
  auto *pending =
      new Invocation{session, FL_METHOD_CALL(g_object_ref(call)), metadata};
  g_dbus_connection_call(
      session->peer, nullptr, legion_control::control_object_path,
      legion_control::control_bus_name, method, arguments,
      metadata ? G_VARIANT_TYPE("(uas)") : G_VARIANT_TYPE("()"),
      G_DBUS_CALL_FLAGS_NONE, metadata ? 5000 : 45000, session->cancel,
      [](GObject *source, GAsyncResult *result, gpointer data) {
        std::unique_ptr<Invocation> pending(static_cast<Invocation *>(data));
        GError *error = nullptr;
        auto *reply = g_dbus_connection_call_finish(G_DBUS_CONNECTION(source),
                                                    result, &error);
        if (pending->session->closed) {
          g_clear_pointer(&reply, g_variant_unref);
          g_clear_error(&error);
          Error(pending->call, "unavailable", "Control session was closed.");
          return;
        }
        if (!reply) {
          ConnectionError(pending->call, error, pending->metadata);
          return;
        }
        g_autoptr(FlValue) value = nullptr;
        if (pending->metadata) {
          guint32 version;
          GVariant *supported;
          g_variant_get(reply, "(u@as)", &version, &supported);
          value = fl_value_new_map();
          fl_value_set_string_take(value, "protocolVersion",
                                   fl_value_new_int(version));
          auto *capabilities = fl_value_new_list();
          GVariantIter values;
          g_variant_iter_init(&values, supported);
          const char *capability;
          while (g_variant_iter_next(&values, "&s", &capability))
            fl_value_append_take(capabilities, fl_value_new_string(capability));
          fl_value_set_string_take(value, "capabilities", capabilities);
          g_variant_unref(supported);
        }
        g_variant_unref(reply);
        fl_method_call_respond_success(pending->call, value, nullptr);
      },
      pending);
}

void FindHostCli(FlMethodCall *call) {
  auto *task = g_task_new(
      nullptr, nullptr,
      [](GObject *, GAsyncResult *result, gpointer data) {
        auto *call = FL_METHOD_CALL(data);
        GError *error = nullptr;
        g_autofree char *path = static_cast<char *>(
            g_task_propagate_pointer(G_TASK(result), &error));
        if (path) {
          g_autoptr(FlValue) value = fl_value_new_string(path);
          fl_method_call_respond_success(call, value, nullptr);
        } else {
          Error(call, "setup",
                error ? error->message : "Could not find the host CLI.");
          g_clear_error(&error);
        }
        g_object_unref(call);
      },
      g_object_ref(call));
  g_task_run_in_thread(
      task, [](GTask *task, gpointer, gpointer, GCancellable *) {
        std::string reason;
        const auto path = legion_control::FindHostLegionCli(&reason);
        if (path.empty() || !g_utf8_validate(path.c_str(), -1, nullptr))
          g_task_return_new_error(task, G_IO_ERROR, G_IO_ERROR_FAILED, "%s",
                                  reason.empty()
                                      ? "The host CLI path is not valid UTF-8."
                                      : reason.c_str());
        else
          g_task_return_pointer(task, g_strdup(path.c_str()), g_free);
      });
  g_object_unref(task);
}
void Handle(FlMethodChannel *, FlMethodCall *call, gpointer data) {
  auto *host = static_cast<Host *>(data);
  const char *method = fl_method_call_get_name(call);
  auto *arguments = fl_method_call_get_args(call);
  if (g_str_equal(method, "findHostCli")) {
    if (arguments && fl_value_get_type(arguments) != FL_VALUE_TYPE_NULL)
      Error(call, "invalid-arguments",
            "Host CLI discovery accepts no caller-selected paths.");
    else
      FindHostCli(call);
    return;
  }
  auto *id = Field(arguments, "session", FL_VALUE_TYPE_STRING);
  if (!id || !g_uuid_string_is_valid(fl_value_get_string(id))) {
    Error(call, "invalid-arguments", "Invalid control session identifier.");
    return;
  }
  const std::string token = fl_value_get_string(id);
  if (g_str_equal(method, "close")) {
    if (host->session && host->session->id == token)
      host->session->Close();
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }
  if (g_str_equal(method, "connect")) {
    if (host->session && !host->session->closed) {
      Error(call, "busy", "A portable control session is already open.");
      return;
    }
    auto *address = Field(arguments, "address", FL_VALUE_TYPE_STRING);
    auto *unit = Field(arguments, "unit", FL_VALUE_TYPE_STRING);
    auto *pid = Field(arguments, "helperPid", FL_VALUE_TYPE_INT);
    if (!address || !unit || !pid || fl_value_get_int(pid) <= 1 ||
        fl_value_get_int(pid) > INT_MAX) {
      Error(call, "invalid-arguments", "Invalid portable helper endpoint.");
      return;
    }
    legion_control::PortableEndpoint endpoint{fl_value_get_string(address),
                                              fl_value_get_string(unit),
                                              guint32(fl_value_get_int(pid))};
    GError *error = nullptr;
    if (!legion_control::ValidatePortableEndpoint(endpoint, &error)) {
      Error(call, "invalid-arguments", error->message);
      g_clear_error(&error);
      return;
    }
    auto session = std::make_shared<Session>();
    session->id = token;
    host->session = session;
    g_object_ref(call);
    legion_control::ConnectPortablePeer(
        endpoint, session->cancel,
        [session, call](GDBusConnection *peer, GError *error) {
          if (session->closed) {
            if (peer) {
              g_dbus_connection_close(peer, nullptr, nullptr, nullptr);
              g_object_unref(peer);
            }
            g_clear_error(&error);
            Error(call, "unavailable",
                  "Control session was closed during startup.");
          } else if (!peer) {
            session->Close();
            ConnectionError(call, error, true);
          } else {
            session->peer = peer;
            fl_method_call_respond_success(call, nullptr, nullptr);
          }
          g_object_unref(call);
        });
    return;
  }
  auto session = host->session;
  if (!session || session->id != token || session->closed || !session->peer ||
      g_dbus_connection_is_closed(session->peer)) {
    Error(call, "unavailable", "Portable control session is unavailable.");
    return;
  }
  if (g_str_equal(method, "getCapabilities"))
    Invoke(session, call, "GetCapabilities", nullptr, true);
  else if (g_str_equal(method, "authorize"))
    Invoke(session, call, "Authorize", nullptr);
  else if (g_str_equal(method, "call")) {
    auto *name = Field(arguments, "method", FL_VALUE_TYPE_STRING);
    auto *values = Field(arguments, "arguments", FL_VALUE_TYPE_LIST);
    auto *parameters = name && values
                           ? Arguments(host->protocol->interfaces[0],
                                       fl_value_get_string(name), values)
                           : nullptr;
    if (!parameters) {
      Error(call, "invalid-arguments",
            "Unsupported control method or arguments.");
      return;
    }
    Invoke(session, call, fl_value_get_string(name), parameters);
    g_variant_unref(parameters);
  } else
    fl_method_call_respond_not_implemented(call, nullptr);
}
} // namespace

void RegisterPortableControlChannel(FlView *view) {
  auto *host = new Host();
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  host->channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "io.github.prnice.legion/portable_control", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(host->channel, Handle, host,
                                            nullptr);
  g_object_set_data_full(G_OBJECT(view), "legion-portable-control", host,
                         [](gpointer data) {
                           auto *host = static_cast<Host *>(data);
                           fl_method_channel_set_method_call_handler(
                               host->channel, nullptr, nullptr, nullptr);
                           delete host;
                         });
  g_signal_connect(
      view, "destroy", G_CALLBACK(+[](GtkWidget *widget, gpointer) {
        g_object_set_data(G_OBJECT(widget), "legion-portable-control", nullptr);
      }),
      nullptr);
}
