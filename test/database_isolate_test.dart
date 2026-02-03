import 'package:flutter_test/flutter_test.dart';
import 'package:accurate_step_counter/accurate_step_counter.dart';
import 'package:accurate_step_counter/src/services/database_isolate.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Unit tests for DatabaseIsolateService
///
/// Note: Tests that actually run the isolate are skipped because isolates
/// cannot share the FFI database factory configured in the main isolate.
/// The isolate will work correctly on real devices where sqflite uses
/// the native SQLite implementation.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DatabaseIsolateService API', () {
    test('can be instantiated', () {
      final service = DatabaseIsolateService();
      expect(service, isNotNull);
      expect(service.isInitialized, isFalse);
    });
  });

  group('DatabaseRequest serialization', () {
    test('toMap and fromMap work correctly', () {
      final request = DatabaseRequest(
        42,
        DatabaseMessageType.insert,
        {'step_count': 100, 'from_time': 12345},
      );

      final map = request.toMap();
      expect(map['id'], 42);
      expect(map['type'], DatabaseMessageType.insert.index);
      expect(map['data']['step_count'], 100);

      final restored = DatabaseRequest.fromMap(map);
      expect(restored.id, 42);
      expect(restored.type, DatabaseMessageType.insert);
      expect(restored.data['step_count'], 100);
    });

    test('all message types can be serialized', () {
      for (final type in DatabaseMessageType.values) {
        final request = DatabaseRequest(1, type, {});
        final map = request.toMap();
        final restored = DatabaseRequest.fromMap(map);
        expect(restored.type, type);
      }
    });
  });

  group('DatabaseResponse serialization', () {
    test('success response toMap and fromMap work correctly', () {
      final response = DatabaseResponse(42, true, 100);

      final map = response.toMap();
      expect(map['id'], 42);
      expect(map['success'], true);
      expect(map['result'], 100);
      expect(map['error'], isNull);

      final restored = DatabaseResponse.fromMap(map);
      expect(restored.id, 42);
      expect(restored.success, true);
      expect(restored.result, 100);
      expect(restored.error, isNull);
    });

    test('error response toMap and fromMap work correctly', () {
      final response = DatabaseResponse(42, false, null, 'Database error');

      final map = response.toMap();
      expect(map['id'], 42);
      expect(map['success'], false);
      expect(map['result'], isNull);
      expect(map['error'], 'Database error');

      final restored = DatabaseResponse.fromMap(map);
      expect(restored.id, 42);
      expect(restored.success, false);
      expect(restored.result, isNull);
      expect(restored.error, 'Database error');
    });

    test('response with list result serializes correctly', () {
      final response = DatabaseResponse(1, true, [
        {'step_count': 100},
        {'step_count': 200},
      ]);

      final map = response.toMap();
      final restored = DatabaseResponse.fromMap(map);

      expect(restored.result, isList);
      expect((restored.result as List).length, 2);
    });
  });

  group('DatabaseMessageType', () {
    test('all expected message types exist', () {
      expect(DatabaseMessageType.values, contains(DatabaseMessageType.insert));
      expect(DatabaseMessageType.values, contains(DatabaseMessageType.query));
      expect(DatabaseMessageType.values, contains(DatabaseMessageType.hasDuplicate));
      expect(DatabaseMessageType.values, contains(DatabaseMessageType.hasOverlapping));
      expect(DatabaseMessageType.values, contains(DatabaseMessageType.deleteBefore));
      expect(DatabaseMessageType.values, contains(DatabaseMessageType.deleteAll));
      expect(DatabaseMessageType.values, contains(DatabaseMessageType.readTotal));
      expect(DatabaseMessageType.values, contains(DatabaseMessageType.getCount));
      expect(DatabaseMessageType.values, contains(DatabaseMessageType.close));
    });
  });

  // Note: These tests are skipped because isolates cannot share
  // the databaseFactoryFfi from the main isolate. The isolate creates its
  // own database connection which doesn't have access to the FFI factory.
  // These would work on a real device but not in unit tests.
  group('DatabaseIsolateService operations', () {
    test('initialize spawns isolate', () {
      // Would test: await service.initialize(); expect(service.isInitialized, isTrue);
    });

    test('insert and query records', () {
      // Would test actual database operations via isolate
    });
  }, skip: 'Isolate tests require real device - isolates cannot share FFI database factory');
}
