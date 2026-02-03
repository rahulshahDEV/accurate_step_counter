import 'dart:async';
import 'dart:isolate';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/step_record.dart';
import '../models/step_record_source.dart';

/// Message types for isolate communication
enum DatabaseMessageType {
  /// Insert a step record
  insert,

  /// Query records with filters
  query,

  /// Check for duplicate records
  hasDuplicate,

  /// Check for overlapping records
  hasOverlapping,

  /// Delete records before a date
  deleteBefore,

  /// Delete all records
  deleteAll,

  /// Read total steps
  readTotal,

  /// Get record count
  getCount,

  /// Close the database and shutdown isolate
  close,
}

/// Request message sent to the database isolate
class DatabaseRequest {
  final int id;
  final DatabaseMessageType type;
  final Map<String, dynamic> data;

  DatabaseRequest(this.id, this.type, this.data);

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.index,
        'data': data,
      };

  static DatabaseRequest fromMap(Map<String, dynamic> map) {
    return DatabaseRequest(
      map['id'] as int,
      DatabaseMessageType.values[map['type'] as int],
      Map<String, dynamic>.from(map['data'] as Map),
    );
  }
}

/// Response message from the database isolate
class DatabaseResponse {
  final int id;
  final bool success;
  final dynamic result;
  final String? error;

  DatabaseResponse(this.id, this.success, this.result, [this.error]);

  Map<String, dynamic> toMap() => {
        'id': id,
        'success': success,
        'result': result,
        'error': error,
      };

  static DatabaseResponse fromMap(Map<String, dynamic> map) {
    return DatabaseResponse(
      map['id'] as int,
      map['success'] as bool,
      map['result'],
      map['error'] as String?,
    );
  }
}

/// Service for managing database operations in a background isolate
///
/// This service offloads all SQLite operations to a separate isolate,
/// preventing database I/O from blocking the main UI thread on low-end devices.
///
/// Example:
/// ```dart
/// final service = DatabaseIsolateService();
/// await service.initialize();
///
/// await service.insertRecord(StepRecord(
///   stepCount: 100,
///   fromTime: DateTime.now().subtract(Duration(minutes: 5)),
///   toTime: DateTime.now(),
///   source: StepRecordSource.foreground,
/// ));
///
/// await service.close();
/// ```
class DatabaseIsolateService {
  static const String _tableName = 'step_records';
  static const String _databaseName = 'accurate_step_counter.db';
  static const int _databaseVersion = 1;

  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  StreamSubscription? _receiveSubscription;

  final Map<int, Completer<dynamic>> _pendingRequests = {};
  int _requestCounter = 0;

  bool _isInitialized = false;
  bool _isShuttingDown = false;

  /// Whether the isolate has been initialized
  bool get isInitialized => _isInitialized;

  /// Initialize the database isolate
  ///
  /// Must be called before any other methods. Spawns a background isolate
  /// and establishes bidirectional communication.
  Future<void> initialize() async {
    if (_isInitialized || _isShuttingDown) return;

    _receivePort = ReceivePort();

    // Spawn the isolate with our entry point
    _isolate = await Isolate.spawn(
      _isolateEntryPoint,
      _receivePort!.sendPort,
    );

    // Wait for the isolate to send its SendPort
    final completer = Completer<SendPort>();
    _receiveSubscription = _receivePort!.listen((message) {
      if (message is SendPort) {
        completer.complete(message);
      } else if (message is Map<String, dynamic>) {
        _handleResponse(DatabaseResponse.fromMap(message));
      }
    });

    _sendPort = await completer.future;
    _isInitialized = true;
  }

  /// Ensure service is initialized
  Future<void> _ensureInitialized() async {
    if (!_isInitialized && !_isShuttingDown) {
      await initialize();
    }
  }

  /// Handle response from the isolate
  void _handleResponse(DatabaseResponse response) {
    final completer = _pendingRequests.remove(response.id);
    if (completer == null) return;

    if (response.success) {
      completer.complete(response.result);
    } else {
      completer.completeError(Exception(response.error ?? 'Unknown error'));
    }
  }

  /// Send a request to the isolate and wait for response
  Future<T> _sendRequest<T>(
    DatabaseMessageType type,
    Map<String, dynamic> data,
  ) async {
    await _ensureInitialized();

    if (_sendPort == null || _isShuttingDown) {
      throw StateError('Database isolate is not running');
    }

    final id = ++_requestCounter;
    final completer = Completer<T>();
    _pendingRequests[id] = completer;

    final request = DatabaseRequest(id, type, data);
    _sendPort!.send(request.toMap());

    return completer.future;
  }

  /// Insert a step record
  Future<void> insertRecord(StepRecord record) async {
    await _sendRequest<void>(DatabaseMessageType.insert, record.toMap());
  }

  /// Check for duplicate records
  Future<bool> hasDuplicateRecord({
    required DateTime fromTime,
    required DateTime toTime,
    int? stepCount,
    StepRecordSource? source,
  }) async {
    return await _sendRequest<bool>(DatabaseMessageType.hasDuplicate, {
      'fromTime': fromTime.toUtc().millisecondsSinceEpoch,
      'toTime': toTime.toUtc().millisecondsSinceEpoch,
      if (stepCount != null) 'stepCount': stepCount,
      if (source != null) 'source': source.index,
    });
  }

  /// Check for overlapping records
  Future<bool> hasOverlappingRecord({
    required DateTime fromTime,
    required DateTime toTime,
  }) async {
    return await _sendRequest<bool>(DatabaseMessageType.hasOverlapping, {
      'fromTime': fromTime.toUtc().millisecondsSinceEpoch,
      'toTime': toTime.toUtc().millisecondsSinceEpoch,
    });
  }

  /// Query records with optional filters
  Future<List<StepRecord>> readRecords({
    DateTime? from,
    DateTime? to,
    StepRecordSource? source,
  }) async {
    final result = await _sendRequest<List<dynamic>>(DatabaseMessageType.query, {
      if (from != null) 'from': from.toUtc().millisecondsSinceEpoch,
      if (to != null) 'to': to.toUtc().millisecondsSinceEpoch,
      if (source != null) 'source': source.index,
    });

    return result
        .map((map) => StepRecord.fromMap(Map<String, dynamic>.from(map as Map)))
        .toList();
  }

  /// Read total steps
  Future<int> readTotalSteps({DateTime? from, DateTime? to}) async {
    return await _sendRequest<int>(DatabaseMessageType.readTotal, {
      if (from != null) 'from': from.toUtc().millisecondsSinceEpoch,
      if (to != null) 'to': to.toUtc().millisecondsSinceEpoch,
    });
  }

  /// Get record count
  Future<int> getRecordCount() async {
    return await _sendRequest<int>(DatabaseMessageType.getCount, {});
  }

  /// Delete records before a date
  Future<void> deleteRecordsBefore(DateTime date) async {
    await _sendRequest<void>(DatabaseMessageType.deleteBefore, {
      'date': date.toUtc().millisecondsSinceEpoch,
    });
  }

  /// Delete all records
  Future<void> deleteAllRecords() async {
    await _sendRequest<void>(DatabaseMessageType.deleteAll, {});
  }

  /// Close the database and shutdown the isolate
  Future<void> close() async {
    if (!_isInitialized || _isShuttingDown) return;

    _isShuttingDown = true;

    try {
      // Send close request and wait for acknowledgment
      await _sendRequest<void>(DatabaseMessageType.close, {});
    } catch (_) {
      // Ignore errors during shutdown
    }

    // Clean up
    await _receiveSubscription?.cancel();
    _receivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);

    _isolate = null;
    _sendPort = null;
    _receivePort = null;
    _receiveSubscription = null;
    _pendingRequests.clear();
    _isInitialized = false;
    _isShuttingDown = false;
  }

  /// Entry point for the database isolate
  static void _isolateEntryPoint(SendPort mainSendPort) async {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    Database? db;

    await for (final message in receivePort) {
      if (message is! Map<String, dynamic>) continue;

      final request = DatabaseRequest.fromMap(message);
      DatabaseResponse response;

      try {
        // Lazy initialize database
        db ??= await _initDatabase();

        final result = await _handleRequest(db, request);
        response = DatabaseResponse(request.id, true, result);

        // Handle close request
        if (request.type == DatabaseMessageType.close) {
          await db.close();
          mainSendPort.send(response.toMap());
          receivePort.close();
          return;
        }
      } catch (e) {
        response = DatabaseResponse(request.id, false, null, e.toString());
      }

      mainSendPort.send(response.toMap());
    }
  }

  /// Initialize the database in the isolate
  static Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      singleInstance: true,
    );
  }

  /// Create database tables (same schema as DatabaseHelper)
  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        step_count INTEGER NOT NULL,
        from_time INTEGER NOT NULL,
        to_time INTEGER NOT NULL,
        source INTEGER NOT NULL,
        confidence REAL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_step_records_time ON $_tableName(from_time, to_time)
    ''');

    await db.execute('''
      CREATE INDEX idx_step_records_source ON $_tableName(source)
    ''');
  }

  /// Handle a request in the isolate
  static Future<dynamic> _handleRequest(
    Database db,
    DatabaseRequest request,
  ) async {
    switch (request.type) {
      case DatabaseMessageType.insert:
        await db.insert(_tableName, request.data);
        return null;

      case DatabaseMessageType.query:
        return _queryRecords(db, request.data);

      case DatabaseMessageType.hasDuplicate:
        return _hasDuplicate(db, request.data);

      case DatabaseMessageType.hasOverlapping:
        return _hasOverlapping(db, request.data);

      case DatabaseMessageType.deleteBefore:
        await db.delete(
          _tableName,
          where: 'to_time < ?',
          whereArgs: [request.data['date']],
        );
        return null;

      case DatabaseMessageType.deleteAll:
        await db.delete(_tableName);
        return null;

      case DatabaseMessageType.readTotal:
        return _readTotal(db, request.data);

      case DatabaseMessageType.getCount:
        final result = await db.rawQuery(
          'SELECT COUNT(*) as count FROM $_tableName',
        );
        return Sqflite.firstIntValue(result) ?? 0;

      case DatabaseMessageType.close:
        return null;
    }
  }

  /// Query records with filters
  static Future<List<Map<String, dynamic>>> _queryRecords(
    Database db,
    Map<String, dynamic> data,
  ) async {
    final conditions = <String>[];
    final args = <dynamic>[];

    if (data.containsKey('from')) {
      conditions.add('to_time > ?');
      args.add(data['from']);
    }
    if (data.containsKey('to')) {
      conditions.add('from_time <= ?');
      args.add(data['to']);
    }
    if (data.containsKey('source')) {
      conditions.add('source = ?');
      args.add(data['source']);
    }

    final results = await db.query(
      _tableName,
      where: conditions.isNotEmpty ? conditions.join(' AND ') : null,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'from_time DESC',
    );

    return results;
  }

  /// Check for duplicate records
  static Future<bool> _hasDuplicate(
    Database db,
    Map<String, dynamic> data,
  ) async {
    const toleranceMs = 60000;
    final fromTime = data['fromTime'] as int;
    final toTime = data['toTime'] as int;

    final fromStart = fromTime - toleranceMs;
    final fromEnd = fromTime + toleranceMs;
    final toStart = toTime - toleranceMs;
    final toEnd = toTime + toleranceMs;

    String whereClause =
        'from_time > ? AND from_time < ? AND to_time > ? AND to_time < ?';
    List<dynamic> whereArgs = [fromStart, fromEnd, toStart, toEnd];

    if (data.containsKey('stepCount')) {
      whereClause += ' AND step_count = ?';
      whereArgs.add(data['stepCount']);
    }

    if (data.containsKey('source')) {
      whereClause += ' AND source = ?';
      whereArgs.add(data['source']);
    }

    final results = await db.query(
      _tableName,
      where: whereClause,
      whereArgs: whereArgs,
      limit: 1,
    );

    return results.isNotEmpty;
  }

  /// Check for overlapping records
  static Future<bool> _hasOverlapping(
    Database db,
    Map<String, dynamic> data,
  ) async {
    final fromMs = data['fromTime'] as int;
    final toMs = data['toTime'] as int;

    final results = await db.query(
      _tableName,
      where: 'from_time < ? AND to_time > ?',
      whereArgs: [toMs, fromMs],
      limit: 1,
    );

    return results.isNotEmpty;
  }

  /// Read total steps with optional filters
  static Future<int> _readTotal(
    Database db,
    Map<String, dynamic> data,
  ) async {
    final conditions = <String>[];
    final args = <dynamic>[];

    if (data.containsKey('from')) {
      conditions.add('to_time > ?');
      args.add(data['from']);
    }
    if (data.containsKey('to')) {
      conditions.add('from_time <= ?');
      args.add(data['to']);
    }

    final whereClause =
        conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';

    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(step_count), 0) as total FROM $_tableName $whereClause',
      args.isNotEmpty ? args : null,
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }
}
