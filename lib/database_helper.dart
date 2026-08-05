import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'dart:io'; // Windows platform check karne ke liye add kiya
import 'package:path_provider/path_provider.dart'; // Sahi path nikalne ke liye add kiya

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  String _profileId = 'default';

  String get activeProfileId => _profileId;
  DatabaseHelper._init();

  String _dbFileForProfile() {
    if (_profileId == 'default') return 'budget_pro.db';
    final safe = _profileId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return 'budget_pro_$safe.db';
  }

  Future<void> setProfile(String profileId, {bool forceReopen = false}) async {
    final next = profileId.trim().isEmpty ? 'default' : profileId.trim();
    if (next == _profileId && !forceReopen) return;
    _profileId = next;
    await closeDb();
  }

  Future<void> deleteProfileDatabase(String profileId) async {
    final id = profileId.trim().isEmpty ? 'default' : profileId.trim();
    if (id == _profileId) {
      await closeDb();
    }
    String dbPath;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final directory = await getApplicationSupportDirectory();
      dbPath = directory.path;
    } else {
      dbPath = await getDatabasesPath();
    }
    final original = _profileId;
    _profileId = id;
    final path = join(dbPath, _dbFileForProfile());
    _profileId = original;
    await deleteDatabase(path);
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB(_dbFileForProfile());
    return _database!;
  }

  // ==== YAHAN CHANGES KI GAYI HAIN ====
  Future<Database> _initDB(String filePath) async {
    String dbPath;

    // Windows/Desktop ke liye path setting taake data delete na ho
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final directory = await getApplicationSupportDirectory();
      dbPath = directory.path;
    } else {
      // Android/iOS ke liye default SQLite path
      dbPath = await getDatabasesPath();
    }

    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 22,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    ).then((db) async {
      await _ensureTransactionColumns(db);
      await _dedupeNamedRows(db, 'accounts', 'name');
      await _dedupeNamedRows(db, 'categories', 'name');
      return db;
    });
  }

  Future<void> _ensureTransactionColumns(Database db) async {
    try {
      final txCols = await db.rawQuery('PRAGMA table_info(transactions)');
      final names = txCols.map((c) => c['name'].toString()).toSet();
      if (!names.contains('category_effect')) {
        await db.execute(
            'ALTER TABLE transactions ADD COLUMN category_effect TEXT');
      }
      if (!names.contains('fx_currency')) {
        await db.execute(
            'ALTER TABLE transactions ADD COLUMN fx_currency TEXT');
      }
      if (!names.contains('fx_amount')) {
        await db
            .execute('ALTER TABLE transactions ADD COLUMN fx_amount REAL');
      }
      if (!names.contains('fx_rate')) {
        await db.execute('ALTER TABLE transactions ADD COLUMN fx_rate REAL');
      }
      if (!names.contains('member_name')) {
        await db.execute(
            'ALTER TABLE transactions ADD COLUMN member_name TEXT');
      }
    } catch (_) {}
  }

  Future<void> _dedupeNamedRows(
      Database db, String table, String nameColumn) async {
    try {
      final rows = await db.query(table, orderBy: 'id ASC');
      final seen = <String>{};
      for (final row in rows) {
        final name = row[nameColumn]?.toString() ?? '';
        if (name.isEmpty) continue;
        if (seen.contains(name)) {
          await db.delete(table, where: 'id = ?', whereArgs: [row['id']]);
        } else {
          seen.add(name);
        }
      }
    } catch (_) {}
  }
  // ====================================

  Future _createDB(Database db, int version) async {
    // Transactions table
    await db.execute('''
      CREATE TABLE transactions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        desc TEXT,
        amount REAL,
        type TEXT,
        account TEXT,
        toAccount TEXT,
        category TEXT,
        sub_category TEXT,
        category_effect TEXT,
        date TEXT,
        imgs TEXT,
        fx_currency TEXT,
        fx_amount REAL,
        fx_rate REAL,
        member_name TEXT
      )
    ''');

    // Accounts table
    await db.execute('''
      CREATE TABLE accounts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        initial_balance REAL
      )
    ''');

    // Categories table
    await db.execute('''
      CREATE TABLE categories(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        budget REAL,
        sub_categories TEXT
      )
    ''');

    // Notes table
    await db.execute('''
      CREATE TABLE notes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        content TEXT,
        color INTEGER,
        reminder TEXT,
        imgs TEXT,
        cat TEXT,
        date TEXT
      )
    ''');

    // Diary table
    await db.execute('''
      CREATE TABLE diary(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        content TEXT,
        cat TEXT,
        date TEXT,
        imgs TEXT,
        reminder TEXT
      )
    ''');

    // Cards table
    await db.execute('''
      CREATE TABLE cards(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        card_holder TEXT,
        card_type TEXT,
        card_number TEXT,
        expiry TEXT,
        cvv TEXT,
        color INTEGER,
        front_image TEXT,
        back_image TEXT
      )
    ''');

    // Family Vault Table
    await db.execute('''
      CREATE TABLE family_vault(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        member_name TEXT,
        doc_type TEXT,
        doc_number TEXT,
        expiry_date TEXT,
        images TEXT,
        timestamp TEXT
      )
    ''');

    // Business cards (scanned; OCR text for master search)
    await db.execute('''
      CREATE TABLE business_cards(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        ocr_text TEXT,
        notes TEXT,
        image_path TEXT,
        created_at TEXT
      )
    ''');

    // Vault Items Table (Passwords)
    await db.execute('''
      CREATE TABLE vault_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        user_id TEXT,
        content TEXT
      )
    ''');

    // Investment portfolio holdings
    await db.execute('''
      CREATE TABLE investments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        asset_type TEXT,
        symbol TEXT,
        quantity REAL,
        avg_buy_price REAL,
        current_price REAL,
        broker TEXT,
        notes TEXT,
        created_date TEXT,
        updated_date TEXT
      )
    ''');

    // Insert default account
    await db.insert('accounts', {'name': 'Cash', 'initial_balance': 0.0});

    // Insert default categories
    await db.insert('categories', {
      'name': 'Food',
      'budget': 0.0,
      'sub_categories': jsonEncode(['Groceries', 'Restaurants', 'Snacks'])
    });
    await db.insert('categories', {
      'name': 'Transport',
      'budget': 0.0,
      'sub_categories': jsonEncode(['Fuel', 'Public Transport', 'Taxi'])
    });
    await db.insert('categories', {
      'name': 'Shopping',
      'budget': 0.0,
      'sub_categories': jsonEncode(['Clothes', 'Electronics', 'Gifts'])
    });
    await db.insert('categories', {
      'name': 'Bills',
      'budget': 0.0,
      'sub_categories':
          jsonEncode(['Electricity', 'Water', 'Internet', 'Mobile'])
    });
    await db.insert('categories', {
      'name': 'Entertainment',
      'budget': 0.0,
      'sub_categories': jsonEncode(['Movies', 'Games', 'Music'])
    });
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 22) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS business_cards(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            ocr_text TEXT,
            notes TEXT,
            image_path TEXT,
            created_at TEXT
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 19) {
      try {
        final txCols = await db.rawQuery('PRAGMA table_info(transactions)');
        if (!txCols.any((c) => c['name'] == 'category_effect')) {
          await db.execute(
              'ALTER TABLE transactions ADD COLUMN category_effect TEXT');
        }
      } catch (_) {}
    }
    if (oldVersion < 20 || oldVersion < 21) {
      await _ensureTransactionColumns(db);
    }
    if (oldVersion < 17) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS investments(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            asset_type TEXT,
            symbol TEXT,
            quantity REAL,
            avg_buy_price REAL,
            current_price REAL,
            broker TEXT,
            notes TEXT,
            created_date TEXT,
            updated_date TEXT
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 18) {
      try {
        final noteCols = await db.rawQuery('PRAGMA table_info(notes)');
        if (!noteCols.any((c) => c['name'] == 'cat')) {
          await db.execute("ALTER TABLE notes ADD COLUMN cat TEXT");
        }
      } catch (_) {}
    }
    if (oldVersion < 16) {
      try {
        final noteCols = await db.rawQuery('PRAGMA table_info(notes)');
        if (!noteCols.any((c) => c['name'] == 'imgs')) {
          await db.execute('ALTER TABLE notes ADD COLUMN imgs TEXT');
        }
      } catch (_) {}
    }
    if (oldVersion < 15) {
      try {
        final diaryCols = await db.rawQuery('PRAGMA table_info(diary)');
        if (!diaryCols.any((c) => c['name'] == 'reminder')) {
          await db.execute('ALTER TABLE diary ADD COLUMN reminder TEXT');
        }
        final noteCols = await db.rawQuery('PRAGMA table_info(notes)');
        if (!noteCols.any((c) => c['name'] == 'reminder')) {
          await db.execute('ALTER TABLE notes ADD COLUMN reminder TEXT');
        }
      } catch (_) {}
    }
    if (oldVersion < 14) {
      // Fix diary table
      try {
        List<Map<String, dynamic>> columns =
            await db.rawQuery("PRAGMA table_info(diary)");
        bool hasCat = columns.any((col) => col['name'] == 'cat');
        bool hasCategory = columns.any((col) => col['name'] == 'category');
        bool hasImgs = columns.any((col) => col['name'] == 'imgs');

        if (!hasCat && hasCategory) {
          await db.execute("ALTER TABLE diary RENAME COLUMN category TO cat");
        } else if (!hasCat && !hasCategory) {
          await db.execute("ALTER TABLE diary ADD COLUMN cat TEXT");
        }
        if (!hasImgs) {
          await db.execute("ALTER TABLE diary ADD COLUMN imgs TEXT");
        }
      } catch (e) {}

      // Fix cards table
      try {
        await db.execute('DROP TABLE IF EXISTS cards');
        await db.execute('''
          CREATE TABLE cards(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            card_holder TEXT,
            card_type TEXT,
            card_number TEXT,
            expiry TEXT,
            cvv TEXT,
            color INTEGER,
            front_image TEXT,
            back_image TEXT
          )
        ''');
      } catch (e) {}

      // Fix vault_items table
      try {
        await db.execute('DROP TABLE IF EXISTS vault_items');
        await db.execute('''
          CREATE TABLE vault_items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            user_id TEXT,
            content TEXT
          )
        ''');
      } catch (e) {}
    }
  }

  // ============== GENERIC METHODS ==============
  Future<int> insert(String table, Map<String, dynamic> row) async {
    final db = await instance.database;
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    final allowed = cols.map((c) => c['name'].toString()).toSet();
    final cleaned = <String, dynamic>{};
    for (final e in row.entries) {
      if (allowed.contains(e.key) && e.key != 'id') {
        cleaned[e.key] = e.value;
      }
    }
    if (cleaned.isEmpty) return 0;
    return await db.insert(table, cleaned);
  }

  Future<List<Map<String, dynamic>>> queryAllRows(String table) async {
    final db = await instance.database;
    return await db.query(table, orderBy: 'id DESC');
  }

  Future<int> update(String table, int id, Map<String, dynamic> row) async {
    final db = await instance.database;
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    final allowed = cols.map((c) => c['name'].toString()).toSet();
    final cleaned = <String, dynamic>{};
    for (final e in row.entries) {
      if (allowed.contains(e.key) && e.key != 'id') {
        cleaned[e.key] = e.value;
      }
    }
    if (cleaned.isEmpty) return 0;
    return await db.update(table, cleaned, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> delete(String table, int id) async {
    final db = await instance.database;
    return await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  // ============== TRANSACTIONS ==============
  Future<List<Map<String, dynamic>>> getTransactions() async =>
      queryAllRows('transactions');
  Future<int> addTransaction(Map<String, dynamic> row) =>
      insert('transactions', row);
  Future<int> updateTransaction(int id, Map<String, dynamic> row) =>
      update('transactions', id, row);
  Future<int> deleteTransaction(int id) => delete('transactions', id);

  // ============== ACCOUNTS ==============
  Future<List<Map<String, dynamic>>> getAccounts() async {
    final db = await instance.database;
    return await db.query('accounts', orderBy: 'name COLLATE NOCASE ASC');
  }

  Future<int> addAccount(Map<String, dynamic> row) => insert('accounts', row);
  Future<int> updateAccount(int id, Map<String, dynamic> row) =>
      update('accounts', id, row);
  Future<int> deleteAccount(int id) => delete('accounts', id);

  // ============== CATEGORIES ==============
  Future<List<Map<String, dynamic>>> getCategories() async {
    final db = await instance.database;
    return await db.query('categories', orderBy: 'name COLLATE NOCASE ASC');
  }

  Future<int> addCategory(Map<String, dynamic> row) =>
      insert('categories', row);
  Future<int> updateCategory(int id, Map<String, dynamic> row) =>
      update('categories', id, row);
  Future<int> deleteCategory(int id) => delete('categories', id);

  // ============== NOTES ==============
  Future<List<Map<String, dynamic>>> getNotes() async {
    final db = await instance.database;
    return await db.query('notes', orderBy: 'id DESC');
  }

  Future<int> addNote(Map<String, dynamic> row) => insert('notes', row);
  Future<int> updateNote(int id, Map<String, dynamic> row) =>
      update('notes', id, row);
  Future<int> deleteNote(int id) => delete('notes', id);

  // ============== CARDS ==============
  Future<List<Map<String, dynamic>>> getCards() async => queryAllRows('cards');
  Future<int> addCard(Map<String, dynamic> row) => insert('cards', row);
  Future<int> updateCard(int id, Map<String, dynamic> row) =>
      update('cards', id, row);
  Future<int> deleteCard(int id) => delete('cards', id);

  // ============== DIARY ==============
  Future<List<Map<String, dynamic>>> getDiary() async => queryAllRows('diary');
  Future<int> addDiary(Map<String, dynamic> row) => insert('diary', row);
  Future<int> updateDiary(int id, Map<String, dynamic> row) =>
      update('diary', id, row);
  Future<int> deleteDiary(int id) => delete('diary', id);

  // ============== FAMILY VAULT ==============
  Future<List<Map<String, dynamic>>> getFamilyVault() async =>
      queryAllRows('family_vault');
  Future<int> addFamilyVault(Map<String, dynamic> row) =>
      insert('family_vault', row);
  Future<int> updateFamilyVault(int id, Map<String, dynamic> row) =>
      update('family_vault', id, row);
  Future<int> deleteFamilyVault(int id) => delete('family_vault', id);

  // ============== BUSINESS CARDS ==============
  Future<List<Map<String, dynamic>>> getBusinessCards() async =>
      queryAllRows('business_cards');
  Future<int> addBusinessCard(Map<String, dynamic> row) =>
      insert('business_cards', row);
  Future<int> updateBusinessCard(int id, Map<String, dynamic> row) =>
      update('business_cards', id, row);
  Future<int> deleteBusinessCard(int id) => delete('business_cards', id);

  /// Master search: matches title, notes, or any OCR text on the card.
  Future<List<Map<String, dynamic>>> searchBusinessCards(String query) async {
    final db = await instance.database;
    final q = query.trim();
    if (q.isEmpty) {
      return await db.query('business_cards', orderBy: 'id DESC');
    }
    final pattern = '%${q.toLowerCase()}%';
    return await db.rawQuery(
      '''SELECT * FROM business_cards
         WHERE lower(ifnull(title, '')) LIKE ?
            OR lower(ifnull(notes, '')) LIKE ?
            OR lower(ifnull(ocr_text, '')) LIKE ?
         ORDER BY id DESC''',
      [pattern, pattern, pattern],
    );
  }

  // ============== VAULT ITEMS ==============
  Future<List<Map<String, dynamic>>> getVaultItems() async =>
      queryAllRows('vault_items');
  Future<int> addVaultItem(Map<String, dynamic> row) =>
      insert('vault_items', row);
  Future<int> updateVaultItem(int id, Map<String, dynamic> row) =>
      update('vault_items', id, row);
  Future<int> deleteVaultItem(int id) => delete('vault_items', id);

  // ============== INVESTMENTS ==============
  Future<List<Map<String, dynamic>>> getInvestments() async {
    final db = await instance.database;
    return await db.query('investments', orderBy: 'updated_date DESC, id DESC');
  }

  Future<int> addInvestment(Map<String, dynamic> row) =>
      insert('investments', row);
  Future<int> updateInvestment(int id, Map<String, dynamic> row) =>
      update('investments', id, row);
  Future<int> deleteInvestment(int id) => delete('investments', id);

  // ============== SEARCH ==============
  Future<List<Map<String, dynamic>>> searchAllTransactions(String query) async {
    final db = await instance.database;
    final pattern = '%$query%';
    return await db.rawQuery(
      '''SELECT * FROM transactions 
         WHERE title LIKE ? OR desc LIKE ? OR category LIKE ? OR account LIKE ? 
         ORDER BY id DESC''',
      [pattern, pattern, pattern, pattern],
    );
  }

  // ============== RESET METHODS ==============
  Future<void> resetDatabase() async {
    final db = await instance.database;
    await db.delete('transactions');
    await db.delete('accounts');
    await db.delete('categories');
    await db.delete('notes');
    await db.delete('cards');
    await db.delete('family_vault');
    await db.delete('business_cards');
    await db.delete('diary');
    await db.delete('vault_items');
    await db.delete('investments');
  }

  Future<void> clearTransactionsOnly() async {
    final db = await instance.database;
    await db.delete('transactions');
  }

  Future<void> closeDb() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
