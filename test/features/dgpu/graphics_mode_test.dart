import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/dgpu/models/graphics_mode.dart';

void main() {
  group('GraphicsModeStatus.parse', () {
    test('parses authoritative combined status', () {
      final status = GraphicsModeStatus.parse('''
{
  "schema_version": 1,
  "selected_mode": "hybrid-auto",
  "effective_dgpu_state": "detached",
  "expected_dgpu_state": "detached",
  "reconciliation": "settled",
  "client_inspection_complete": true,
  "active_clients": [
    {
      "pid": 4242,
      "comm": "renderer",
      "devices": ["/dev/nvidia0", "/dev/dri/card0"]
    }
  ],
  "available_modes": [
    "hybrid",
    "hybrid-igpu-only",
    "hybrid-auto",
    "discrete"
  ],
  "reconciliation_attempts": 2
}
''');

      expect(status.selectedMode, GraphicsMode.hybridAuto);
      expect(status.effectiveState, DgpuTopology.detached);
      expect(status.expectedState, DgpuTopology.detached);
      expect(status.reconciliation, GraphicsReconciliation.settled);
      expect(status.clientInspectionComplete, isTrue);
      expect(status.availableModes, GraphicsMode.values);
      expect(status.reconciliationAttempts, 2);
      expect(status.activeClients, [
        const GraphicsModeClient(
          pid: 4242,
          command: 'renderer',
          devices: ['/dev/nvidia0', '/dev/dri/card0'],
        ),
      ]);
    });

    test('accepts missing optional reconciliation attempts', () {
      final status = GraphicsModeStatus.parse(_statusJson);

      expect(status.reconciliationAttempts, isNull);
    });

    test('rejects unknown selected mode', () {
      expect(
        () => GraphicsModeStatus.parse(
          _statusJson.replaceFirst('"hybrid"', '"future-mode"'),
        ),
        throwsFormatException,
      );
    });

    test('rejects unknown topology', () {
      expect(
        () => GraphicsModeStatus.parse(
          _statusJson.replaceFirst('"attached"', '"mostly-attached"'),
        ),
        throwsFormatException,
      );
    });

    test('rejects malformed client records', () {
      expect(
        () => GraphicsModeStatus.parse(
          _statusJson.replaceFirst('"active_clients": []', '''
"active_clients": [{"pid": "4242", "comm": "renderer", "devices": []}]
'''),
        ),
        throwsFormatException,
      );
    });
  });
}

const _statusJson = '''
{
  "schema_version": 1,
  "selected_mode": "hybrid",
  "effective_dgpu_state": "attached",
  "expected_dgpu_state": "attached",
  "reconciliation": "settled",
  "client_inspection_complete": false,
  "active_clients": [],
  "available_modes": ["hybrid", "hybrid-igpu-only", "hybrid-auto", "discrete"]
}
''';
