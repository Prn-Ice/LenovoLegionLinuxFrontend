import 'dart:async';

import 'package:dbus/dbus.dart';

import 'platform_tray.dart';
import 'tray_menu.dart';

const _watcher = 'org.kde.StatusNotifierWatcher';
const _itemInterface = 'org.kde.StatusNotifierItem';
const _menuInterface = 'com.canonical.dbusmenu';

/// Owns a dedicated session-bus connection. One instance is used per tray.
class DBusTrayTransport implements TrayTransport {
  DBusTrayTransport({DBusClient? client})
    : _client = client ?? DBusClient.session();

  final DBusClient _client;
  final _item = _StatusItem();
  final _menu = _Menu();
  StreamSubscription<DBusNameOwnerChangedEvent>? _subscription;
  final _changes = StreamController<bool>.broadcast();
  bool _closed = false;

  @override
  Stream<bool> get watcherChanges => _changes.stream;

  @override
  Future<void> open() async {
    _subscription = _client.nameOwnerChanged.listen(
      (event) {
        if (event.name == _watcher && !_closed) {
          _changes.add(event.newOwner != null);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!_closed) _changes.addError(error, stack);
      },
    );
    await _client.registerObject(_item);
    await _client.registerObject(_menu);
  }

  @override
  Future<bool> watcherPresent() => _client.nameHasOwner(_watcher);

  @override
  Future<void> register() async {
    final watcher = DBusRemoteObject(
      _client,
      name: _watcher,
      path: DBusObjectPath('/StatusNotifierWatcher'),
    );
    // The object path form registers the caller's unique bus name.
    await watcher.callMethod(_watcher, 'RegisterStatusNotifierItem', [
      DBusString('/StatusNotifierItem'),
    ], noAutoStart: true);
  }

  @override
  Future<void> updateMenu(List<TrayMenuItem> items) => _menu.update(items);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    await _client.close();
    await _changes.close();
  }
}

class _StatusItem extends DBusObject {
  _StatusItem() : super(DBusObjectPath('/StatusNotifierItem'));

  Map<String, DBusValue> get properties => {
    'Category': DBusString('Hardware'),
    'Id': DBusString('legion-frontend'),
    'Title': DBusString('Legion'),
    'Status': DBusString('Active'),
    'WindowId': DBusUint32(0),
    'IconName': DBusString('computer'),
    'IconPixmap': DBusArray(DBusSignature('(iiay)')),
    'OverlayIconName': DBusString(''),
    'OverlayIconPixmap': DBusArray(DBusSignature('(iiay)')),
    'AttentionIconName': DBusString(''),
    'AttentionIconPixmap': DBusArray(DBusSignature('(iiay)')),
    'AttentionMovieName': DBusString(''),
    'ToolTip': DBusStruct([
      DBusString('computer'),
      DBusArray(DBusSignature('(iiay)')),
      DBusString('Legion'),
      DBusString(''),
    ]),
    'ItemIsMenu': DBusBoolean(true),
    'Menu': DBusObjectPath('/MenuBar'),
  };

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface != _itemInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final value = properties[name];
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async =>
      interface == _itemInterface
      ? DBusGetAllPropertiesResponse(properties)
      : DBusMethodErrorResponse.unknownInterface();
}

class _Menu extends DBusObject {
  _Menu() : super(DBusObjectPath('/MenuBar'));

  List<TrayMenuItem> _items = [
    TrayMenuItem(id: 1, label: 'Status unavailable'),
  ];
  int _revision = 0;

  Future<void> update(List<TrayMenuItem> items) async {
    final ids = <int>{0};
    void validate(List<TrayMenuItem> entries) {
      for (final item in entries) {
        if (!ids.add(item.id) || item.id < 1) {
          throw ArgumentError('Menu IDs must be unique positive integers');
        }
        if (item.toggleType != null &&
            item.toggleType != 'radio' &&
            item.toggleType != 'checkmark') {
          throw ArgumentError('Invalid toggle type');
        }
        validate(item.children);
      }
    }

    validate(items);
    _items = List.unmodifiable(items);
    _revision = (_revision + 1) & 0xffffffff;
    await emitSignal(_menuInterface, 'LayoutUpdated', [
      DBusUint32(_revision),
      DBusInt32(0),
    ]);
  }

  TrayMenuItem? find(int id, [List<TrayMenuItem>? entries]) {
    for (final item in entries ?? _items) {
      if (item.id == id) return item;
      final child = find(id, item.children);
      if (child != null) return child;
    }
    return null;
  }

  Map<String, DBusValue> itemProperties(TrayMenuItem item, List<String> names) {
    final values = <String, DBusValue>{
      'label': DBusString(item.label),
      'enabled': DBusBoolean(item.enabled),
      if (item.children.isNotEmpty) 'children-display': DBusString('submenu'),
      if (item.toggleType != null && item.checked != null)
        'toggle-type': DBusString(item.toggleType!),
      if (item.toggleType != null && item.checked != null)
        'toggle-state': DBusInt32(item.checked! ? 1 : 0),
    };
    if (names.isEmpty) return values;
    return Map.fromEntries(
      values.entries.where((entry) => names.contains(entry.key)),
    );
  }

  DBusStruct layout(int id, int depth, List<String> names) {
    final item = id == 0 ? null : find(id);
    final children = item?.children ?? _items;
    return DBusStruct([
      DBusInt32(id),
      DBusDict.stringVariant(item == null ? {} : itemProperties(item, names)),
      DBusArray(
        DBusSignature('v'),
        depth == 0
            ? []
            : children.map(
                (child) => DBusVariant(
                  layout(child.id, depth < 0 ? -1 : depth - 1, names),
                ),
              ),
      ),
    ]);
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface != _menuInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final value = {
      'Version': DBusUint32(3),
      'TextDirection': DBusString('ltr'),
      'Status': DBusString('normal'),
      'IconThemePath': DBusArray.string([]),
    }[name];
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != _menuInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    return DBusGetAllPropertiesResponse({
      'Version': DBusUint32(3),
      'TextDirection': DBusString('ltr'),
      'Status': DBusString('normal'),
      'IconThemePath': DBusArray.string([]),
    });
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != _menuInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    if (call.name == 'GetLayout' && call.signature == DBusSignature('iias')) {
      final id = call.values[0].asInt32();
      if (id != 0 && find(id) == null) {
        return DBusMethodErrorResponse.invalidArgs();
      }
      return DBusMethodSuccessResponse([
        DBusUint32(_revision),
        layout(
          id,
          call.values[1].asInt32(),
          call.values[2].asStringArray().toList(),
        ),
      ]);
    }
    if (call.name == 'Event' && call.signature == DBusSignature('isvu')) {
      final item = find(call.values[0].asInt32());
      if (item == null) return DBusMethodErrorResponse.invalidArgs();
      if (call.values[1].asString() == 'clicked' && item.enabled) {
        item.onActivate?.call();
      }
      return DBusMethodSuccessResponse();
    }
    if (call.name == 'GetGroupProperties' &&
        call.signature == DBusSignature('aias')) {
      final names = call.values[1].asStringArray().toList();
      final values = <DBusValue>[];
      for (final id in call.values[0].asInt32Array()) {
        final item = find(id);
        if (item != null) {
          values.add(
            DBusStruct([
              DBusInt32(id),
              DBusDict.stringVariant(itemProperties(item, names)),
            ]),
          );
        } else if (id == 0) {
          values.add(DBusStruct([DBusInt32(0), DBusDict.stringVariant({})]));
        }
      }
      return DBusMethodSuccessResponse([
        DBusArray(DBusSignature('(ia{sv})'), values),
      ]);
    }
    if (call.name == 'GetProperty' && call.signature == DBusSignature('is')) {
      final item = find(call.values[0].asInt32());
      final name = call.values[1].asString();
      final value = item == null ? null : itemProperties(item, [name])[name];
      if (value == null) return DBusMethodErrorResponse.invalidArgs();
      return DBusMethodSuccessResponse([DBusVariant(value)]);
    }
    if (call.name == 'AboutToShow' && call.signature == DBusSignature('i')) {
      final id = call.values[0].asInt32();
      if (id != 0 && find(id) == null) {
        return DBusMethodErrorResponse.invalidArgs();
      }
      return DBusMethodSuccessResponse([DBusBoolean(false)]);
    }
    return DBusMethodErrorResponse.unknownMethod();
  }
}
