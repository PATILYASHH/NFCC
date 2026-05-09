import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/nfc_tag.dart';
import '../models/automation.dart';
import '../models/condition_branch.dart';
import '../models/action_item.dart';
import '../models/tag_scan_log.dart';
import '../models/paired_pc.dart';
import '../models/tracker.dart';
import '../models/tracker_log.dart';
import '../models/todo.dart';
import '../models/todo_completion.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._();
  factory DatabaseService() => _instance;
  DatabaseService._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'nfcc.db');
    return openDatabase(
      path,
      version: 3,
      onConfigure: (db) async {
        // sqflite defaults to FK off — turn it on so ON DELETE CASCADE works.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, v) async {
        await _onCreate(db, v);
        await _createTrackerTodoTables(db);
        await _addTodoReminderTime(db);
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) await _createTrackerTodoTables(db);
        if (oldV < 3) await _addTodoReminderTime(db);
      },
    );
  }

  Future<void> _addTodoReminderTime(Database db) async {
    try {
      await db.execute('ALTER TABLE todos ADD COLUMN reminder_time TEXT');
    } catch (_) { /* column may already exist */ }
  }

  Future<void> _createTrackerTodoTables(Database db) async {
    await db.execute('''
      CREATE TABLE trackers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        unit TEXT,
        per_tap_amount REAL NOT NULL DEFAULT 1,
        daily_goal REAL,
        icon_code INTEGER NOT NULL,
        color_value INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE tracker_tags (
        tracker_id INTEGER NOT NULL,
        tag_uid TEXT NOT NULL,
        PRIMARY KEY (tracker_id, tag_uid),
        FOREIGN KEY (tracker_id) REFERENCES trackers(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE tracker_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tracker_id INTEGER NOT NULL,
        tag_uid TEXT,
        value REAL NOT NULL,
        state TEXT,
        ts TEXT NOT NULL,
        FOREIGN KEY (tracker_id) REFERENCES trackers(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE todos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        recurrence TEXT NOT NULL DEFAULT 'daily',
        streak INTEGER NOT NULL DEFAULT 0,
        best_streak INTEGER NOT NULL DEFAULT 0,
        icon_code INTEGER NOT NULL,
        color_value INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE todo_tags (
        todo_id INTEGER NOT NULL,
        tag_uid TEXT NOT NULL,
        PRIMARY KEY (todo_id, tag_uid),
        FOREIGN KEY (todo_id) REFERENCES todos(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE todo_completions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        todo_id INTEGER NOT NULL,
        tag_uid TEXT,
        completed_at TEXT NOT NULL,
        date_key TEXT NOT NULL,
        FOREIGN KEY (todo_id) REFERENCES todos(id) ON DELETE CASCADE,
        UNIQUE (todo_id, date_key)
      )
    ''');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE nfc_tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uid TEXT UNIQUE NOT NULL,
        tag_type TEXT,
        technology TEXT,
        nickname TEXT,
        first_scanned TEXT NOT NULL,
        last_scanned TEXT NOT NULL,
        scan_count INTEGER DEFAULT 1,
        automation_id INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE automations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        tag_uid TEXT,
        is_enabled INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE condition_branches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        automation_id INTEGER NOT NULL,
        order_index INTEGER NOT NULL,
        condition_type TEXT NOT NULL,
        params TEXT NOT NULL DEFAULT '{}',
        FOREIGN KEY (automation_id) REFERENCES automations(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE action_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        condition_branch_id INTEGER NOT NULL,
        order_index INTEGER NOT NULL,
        target TEXT NOT NULL,
        action_type TEXT NOT NULL,
        params TEXT NOT NULL DEFAULT '{}',
        delay_ms INTEGER DEFAULT 0,
        FOREIGN KEY (condition_branch_id) REFERENCES condition_branches(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE tag_scan_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tag_uid TEXT NOT NULL,
        tag_nickname TEXT,
        scanned_at TEXT NOT NULL,
        automation_name TEXT,
        branch_matched TEXT,
        success INTEGER DEFAULT 1,
        error_message TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE paired_pcs (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        ip TEXT NOT NULL,
        port INTEGER NOT NULL,
        pairing_token TEXT NOT NULL,
        paired_at TEXT NOT NULL
      )
    ''');
  }

  // ── NFC Tags ─────────────────────────────────────────────────────────────

  Future<NfcTag?> getTagByUid(String uid) async {
    final db = await database;
    final rows = await db.query('nfc_tags', where: 'uid = ?', whereArgs: [uid]);
    if (rows.isEmpty) return null;
    return NfcTag.fromMap(rows.first);
  }

  Future<List<NfcTag>> getAllTags() async {
    final db = await database;
    final rows = await db.query('nfc_tags', orderBy: 'last_scanned DESC');
    return rows.map(NfcTag.fromMap).toList();
  }

  Future<int> insertTag(NfcTag tag) async {
    final db = await database;
    return db.insert('nfc_tags', tag.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> updateTag(NfcTag tag) async {
    final db = await database;
    await db.update('nfc_tags', tag.toMap(),
        where: 'id = ?', whereArgs: [tag.id]);
  }

  Future<void> incrementTagScan(String uid) async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE nfc_tags
      SET scan_count = scan_count + 1, last_scanned = ?
      WHERE uid = ?
    ''', [DateTime.now().toIso8601String(), uid]);
  }

  Future<void> deleteTag(int id) async {
    final db = await database;
    await db.delete('nfc_tags', where: 'id = ?', whereArgs: [id]);
  }

  // ── Automations ──────────────────────────────────────────────────────────

  Future<List<Automation>> getAllAutomations() async {
    final db = await database;
    final rows = await db.query('automations', orderBy: 'updated_at DESC');
    final automations = <Automation>[];
    for (final row in rows) {
      final branches = await getBranchesForAutomation(row['id'] as int);
      automations.add(Automation.fromMap(row, branches));
    }
    return automations;
  }

  Future<Automation?> getAutomationByTagUid(String uid) async {
    final db = await database;
    final rows = await db.query('automations',
        where: 'tag_uid = ? AND is_enabled = 1', whereArgs: [uid]);
    if (rows.isEmpty) return null;
    final branches = await getBranchesForAutomation(rows.first['id'] as int);
    return Automation.fromMap(rows.first, branches);
  }

  Future<Automation?> getAutomationById(int id) async {
    final db = await database;
    final rows =
        await db.query('automations', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final branches = await getBranchesForAutomation(id);
    return Automation.fromMap(rows.first, branches);
  }

  Future<int> insertAutomation(Automation automation) async {
    final db = await database;
    return db.transaction((txn) async {
      final id = await txn.insert('automations', automation.toMap());
      for (final branch in automation.branches) {
        await _insertBranchTxn(
          txn,
          branch.copyWith(id: null, automationId: id),
        );
      }
      return id;
    });
  }

  Future<void> updateAutomation(Automation automation) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('automations', automation.toMap(),
          where: 'id = ?', whereArgs: [automation.id]);
      // Replace all branches. action_items cascade-delete via FK.
      await txn.delete('condition_branches',
          where: 'automation_id = ?', whereArgs: [automation.id]);
      for (final branch in automation.branches) {
        await _insertBranchTxn(
          txn,
          // Strip the old PK so SQLite assigns a fresh one — old IDs may
          // belong to rows we just deleted, but explicit-PK reinsert is
          // brittle if anything ever leaves orphans.
          branch.copyWith(id: null, automationId: automation.id),
        );
      }
    });
  }

  Future<void> deleteAutomation(int id) async {
    final db = await database;
    await db.delete('automations', where: 'id = ?', whereArgs: [id]);
  }

  // ── Condition Branches ───────────────────────────────────────────────────

  Future<List<ConditionBranch>> getBranchesForAutomation(
      int automationId) async {
    final db = await database;
    final rows = await db.query('condition_branches',
        where: 'automation_id = ?',
        whereArgs: [automationId],
        orderBy: 'order_index ASC');
    final branches = <ConditionBranch>[];
    for (final row in rows) {
      final actions = await getActionsForBranch(row['id'] as int);
      branches.add(ConditionBranch.fromMap(row, actions));
    }
    return branches;
  }

  Future<int> _insertBranchTxn(
      DatabaseExecutor txn, ConditionBranch branch) async {
    final id = await txn.insert('condition_branches', branch.toMap());
    for (final action in branch.actions) {
      await txn.insert(
        'action_items',
        action.copyWith(id: null, conditionBranchId: id).toMap(),
      );
    }
    return id;
  }

  // ── Action Items ─────────────────────────────────────────────────────────

  Future<List<ActionItem>> getActionsForBranch(int branchId) async {
    final db = await database;
    final rows = await db.query('action_items',
        where: 'condition_branch_id = ?',
        whereArgs: [branchId],
        orderBy: 'order_index ASC');
    return rows.map(ActionItem.fromMap).toList();
  }

  // ── Tag Scan Logs ────────────────────────────────────────────────────────

  Future<void> insertScanLog(TagScanLog log) async {
    final db = await database;
    await db.insert('tag_scan_logs', log.toMap());
  }

  Future<List<TagScanLog>> getRecentScans({int limit = 20}) async {
    final db = await database;
    final rows = await db.query('tag_scan_logs',
        orderBy: 'scanned_at DESC', limit: limit);
    return rows.map(TagScanLog.fromMap).toList();
  }

  Future<List<TagScanLog>> getScansForTag(String uid) async {
    final db = await database;
    final rows = await db.query('tag_scan_logs',
        where: 'tag_uid = ?', whereArgs: [uid], orderBy: 'scanned_at DESC');
    return rows.map(TagScanLog.fromMap).toList();
  }

  // ── Paired PCs ───────────────────────────────────────────────────────────

  Future<List<PairedPc>> getPairedPcs() async {
    final db = await database;
    final rows = await db.query('paired_pcs', orderBy: 'paired_at DESC');
    return rows.map(PairedPc.fromMap).toList();
  }

  Future<void> insertPairedPc(PairedPc pc) async {
    final db = await database;
    await db.insert('paired_pcs', pc.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deletePairedPc(String id) async {
    final db = await database;
    await db.delete('paired_pcs', where: 'id = ?', whereArgs: [id]);
  }

  // ── Trackers ─────────────────────────────────────────────────────────────

  Future<List<String>> _tagsForTracker(Database db, int trackerId) async {
    final rows = await db.query('tracker_tags',
        where: 'tracker_id = ?', whereArgs: [trackerId]);
    return rows.map((r) => r['tag_uid'] as String).toList();
  }

  Future<List<Tracker>> getAllTrackers() async {
    final db = await database;
    final rows = await db.query('trackers', orderBy: 'updated_at DESC');
    final out = <Tracker>[];
    for (final r in rows) {
      final tags = await _tagsForTracker(db, r['id'] as int);
      out.add(Tracker.fromMap(r, tagUids: tags));
    }
    return out;
  }

  Future<Tracker?> getTrackerById(int id) async {
    final db = await database;
    final rows = await db.query('trackers', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final tags = await _tagsForTracker(db, id);
    return Tracker.fromMap(rows.first, tagUids: tags);
  }

  Future<List<Tracker>> getTrackersForTagUid(String uid) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT t.* FROM trackers t
      INNER JOIN tracker_tags tt ON tt.tracker_id = t.id
      WHERE tt.tag_uid = ?
    ''', [uid]);
    final out = <Tracker>[];
    for (final r in rows) {
      final tags = await _tagsForTracker(db, r['id'] as int);
      out.add(Tracker.fromMap(r, tagUids: tags));
    }
    return out;
  }

  Future<int> insertTracker(Tracker t) async {
    final db = await database;
    final id = await db.insert('trackers', t.toMap());
    for (final uid in t.tagUids) {
      await db.insert(
        'tracker_tags',
        {'tracker_id': id, 'tag_uid': uid},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    return id;
  }

  Future<void> updateTracker(Tracker t) async {
    final db = await database;
    await db
        .update('trackers', t.toMap(), where: 'id = ?', whereArgs: [t.id]);
    await db.delete('tracker_tags',
        where: 'tracker_id = ?', whereArgs: [t.id]);
    for (final uid in t.tagUids) {
      await db.insert(
        'tracker_tags',
        {'tracker_id': t.id, 'tag_uid': uid},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> deleteTracker(int id) async {
    final db = await database;
    await db.delete('trackers', where: 'id = ?', whereArgs: [id]);
  }

  // ── Tracker Logs ─────────────────────────────────────────────────────────

  Future<int> insertTrackerLog(TrackerLog log) async {
    final db = await database;
    return db.insert('tracker_logs', log.toMap());
  }

  Future<List<TrackerLog>> getLogsForTracker(int trackerId, {int limit = 100}) async {
    final db = await database;
    final rows = await db.query('tracker_logs',
        where: 'tracker_id = ?',
        whereArgs: [trackerId],
        orderBy: 'ts DESC',
        limit: limit);
    return rows.map(TrackerLog.fromMap).toList();
  }

  Future<TrackerLog?> getLastLogForTracker(int trackerId) async {
    final db = await database;
    final rows = await db.query('tracker_logs',
        where: 'tracker_id = ?',
        whereArgs: [trackerId],
        orderBy: 'ts DESC',
        limit: 1);
    if (rows.isEmpty) return null;
    return TrackerLog.fromMap(rows.first);
  }

  /// Total value logged today (local day) for a tracker.
  Future<double> getTodayTotal(int trackerId) async {
    final db = await database;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toIso8601String();
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(value), 0) AS total FROM tracker_logs
      WHERE tracker_id = ? AND ts >= ?
    ''', [trackerId, start]);
    return (rows.first['total'] as num).toDouble();
  }

  Future<void> deleteTrackerLog(int id) async {
    final db = await database;
    await db.delete('tracker_logs', where: 'id = ?', whereArgs: [id]);
  }

  // ── Todos ───────────────────────────────────────────────────────────────

  Future<List<String>> _tagsForTodo(Database db, int todoId) async {
    final rows = await db.query('todo_tags',
        where: 'todo_id = ?', whereArgs: [todoId]);
    return rows.map((r) => r['tag_uid'] as String).toList();
  }

  Future<bool> _todoDoneToday(Database db, int todoId) async {
    final key = TodoCompletion.dateKeyFor(DateTime.now());
    final rows = await db.query('todo_completions',
        where: 'todo_id = ? AND date_key = ?', whereArgs: [todoId, key]);
    return rows.isNotEmpty;
  }

  Future<List<Todo>> getAllTodos() async {
    final db = await database;
    final rows = await db.query('todos', orderBy: 'updated_at DESC');
    final out = <Todo>[];
    for (final r in rows) {
      final tags = await _tagsForTodo(db, r['id'] as int);
      final done = await _todoDoneToday(db, r['id'] as int);
      out.add(Todo.fromMap(r, tagUids: tags, doneToday: done));
    }
    return out;
  }

  Future<Todo?> getTodoById(int id) async {
    final db = await database;
    final rows = await db.query('todos', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final tags = await _tagsForTodo(db, id);
    final done = await _todoDoneToday(db, id);
    return Todo.fromMap(rows.first, tagUids: tags, doneToday: done);
  }

  Future<List<Todo>> getTodosForTagUid(String uid) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT t.* FROM todos t
      INNER JOIN todo_tags tt ON tt.todo_id = t.id
      WHERE tt.tag_uid = ?
    ''', [uid]);
    final out = <Todo>[];
    for (final r in rows) {
      final tags = await _tagsForTodo(db, r['id'] as int);
      final done = await _todoDoneToday(db, r['id'] as int);
      out.add(Todo.fromMap(r, tagUids: tags, doneToday: done));
    }
    return out;
  }

  Future<int> insertTodo(Todo t) async {
    final db = await database;
    final id = await db.insert('todos', t.toMap());
    for (final uid in t.tagUids) {
      await db.insert(
        'todo_tags',
        {'todo_id': id, 'tag_uid': uid},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    return id;
  }

  Future<void> updateTodo(Todo t) async {
    final db = await database;
    await db.update('todos', t.toMap(), where: 'id = ?', whereArgs: [t.id]);
    await db
        .delete('todo_tags', where: 'todo_id = ?', whereArgs: [t.id]);
    for (final uid in t.tagUids) {
      await db.insert(
        'todo_tags',
        {'todo_id': t.id, 'tag_uid': uid},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> deleteTodo(int id) async {
    final db = await database;
    await db.delete('todos', where: 'id = ?', whereArgs: [id]);
  }

  // ── Todo Completions ────────────────────────────────────────────────────

  /// Toggle today's completion. Returns new doneToday state.
  Future<bool> toggleTodoCompletionToday(int todoId, {String? tagUid}) async {
    final db = await database;
    final key = TodoCompletion.dateKeyFor(DateTime.now());
    final existing = await db.query('todo_completions',
        where: 'todo_id = ? AND date_key = ?', whereArgs: [todoId, key]);
    if (existing.isNotEmpty) {
      await db.delete('todo_completions',
          where: 'todo_id = ? AND date_key = ?', whereArgs: [todoId, key]);
      await _recomputeStreak(db, todoId);
      return false;
    }
    await db.insert('todo_completions', {
      'todo_id': todoId,
      'tag_uid': tagUid,
      'completed_at': DateTime.now().toIso8601String(),
      'date_key': key,
    });
    await _recomputeStreak(db, todoId);
    return true;
  }

  Future<void> _recomputeStreak(Database db, int todoId) async {
    // Streak = consecutive days (including today or yesterday) completed.
    final rows = await db.query('todo_completions',
        where: 'todo_id = ?',
        whereArgs: [todoId],
        orderBy: 'date_key DESC');
    final done = rows.map((r) => r['date_key'] as String).toSet();
    var streak = 0;
    var cursor = DateTime.now();
    // Allow streak to hold if today missing but yesterday done.
    if (!done.contains(TodoCompletion.dateKeyFor(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    while (done.contains(TodoCompletion.dateKeyFor(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    final existing = await db
        .query('todos', where: 'id = ?', whereArgs: [todoId], limit: 1);
    if (existing.isEmpty) return;
    final best = (existing.first['best_streak'] as int? ?? 0);
    await db.update(
      'todos',
      {
        'streak': streak,
        'best_streak': streak > best ? streak : best,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [todoId],
    );
  }

  Future<List<TodoCompletion>> getCompletionsForTodo(int todoId, {int limit = 60}) async {
    final db = await database;
    final rows = await db.query('todo_completions',
        where: 'todo_id = ?',
        whereArgs: [todoId],
        orderBy: 'completed_at DESC',
        limit: limit);
    return rows.map(TodoCompletion.fromMap).toList();
  }
}
