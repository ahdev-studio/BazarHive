import 'package:sqflite/sqflite.dart';
import 'package:flutter/material.dart';
import '../models/category.dart';
import '../models/item.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static const String categoriesTable = 'categories';
  static const String itemsTable = 'items';
  static const String boughtItemsTable = 'bought_items';
  static const String profileTable = 'profile';
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  // Private constructor for singleton pattern
  DatabaseHelper._internal();

  // Factory constructor to return the same instance
  factory DatabaseHelper() {
    return _instance;
  }

  // Database getter, initializes if not exists
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // Get the database file path
  Future<String> getDbPath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, 'bazarhive.db');
  }

  // Close the database connection
  Future<void> closeDatabase() async {
    final db = _database;
    if (db != null && db.isOpen) {
      await db.close();
      _database = null;
    }
  }

  // Initialize the database
  Future<Database> _initDatabase() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'bazarhive.db');

      return await openDatabase(
        path,
        version: 9, // Final version for this fix
        onCreate: (db, version) async {
          // This block is for brand new installations.
          await db.execute('''
            CREATE TABLE $categoriesTable (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT UNIQUE NOT NULL,
              color INTEGER NOT NULL,
              imagePath TEXT
            )
          ''');

          await db.execute('''
            CREATE TABLE $itemsTable (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              categoryId INTEGER NOT NULL,
              price REAL NOT NULL,
              imagePath TEXT,
              FOREIGN KEY (categoryId) REFERENCES categories(id) ON DELETE CASCADE
            )
          ''');

          await db.execute('''
            CREATE TABLE $boughtItemsTable(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              quantity REAL NOT NULL,
              unit TEXT NOT NULL,
              price REAL NOT NULL,
              category_name TEXT,
              category_id INTEGER,
              status INTEGER NOT NULL DEFAULT 0,
              date INTEGER,
              categoryColor INTEGER,
              unitPrice REAL,
              imagePath TEXT,
              boughtTime INTEGER, -- Kept for migration from v1
              category TEXT -- Kept for migration from v1
            )
          ''');

          await db.execute('''
            CREATE TABLE $profileTable(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT,
              email TEXT,
              phone TEXT,
              currency TEXT,
              profile_picture BLOB
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // This block handles migrations for existing users.
          if (oldVersion < 2) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS $boughtItemsTable(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL, quantity REAL NOT NULL, unit TEXT NOT NULL, price REAL NOT NULL,
                category TEXT NOT NULL, categoryColor INTEGER NOT NULL, unitPrice REAL NOT NULL,
                boughtTime INTEGER NOT NULL
              )
            ''');
          }
          if (oldVersion < 3) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS $profileTable(
                id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, email TEXT, phone TEXT, currency TEXT, profile_picture BLOB
              )
            ''');
          }
          if (oldVersion < 4) {
            try { await db.execute('ALTER TABLE $categoriesTable ADD COLUMN imagePath TEXT'); } catch (e) { /* ignored */ }
          }
          if (oldVersion < 7) {
              try { await db.execute('ALTER TABLE $boughtItemsTable ADD COLUMN date INTEGER'); } catch (e) { /* ignored */ }
              try { await db.execute('ALTER TABLE $boughtItemsTable ADD COLUMN status INTEGER NOT NULL DEFAULT 0'); } catch (e) { /* ignored */ }
              try { await db.execute('ALTER TABLE $boughtItemsTable ADD COLUMN imagePath TEXT'); } catch (e) { /* ignored */ }
              try { await db.execute('ALTER TABLE $boughtItemsTable ADD COLUMN category_id INTEGER'); } catch (e) { /* ignored */ }
              try { await db.execute('ALTER TABLE $boughtItemsTable ADD COLUMN category_name TEXT'); } catch (e) { /* ignored */ }
              try { await db.rawUpdate('UPDATE $boughtItemsTable SET date = boughtTime WHERE date IS NULL'); } catch (e) { /* ignored */ }
              try { await db.rawUpdate('UPDATE $boughtItemsTable SET category_name = category WHERE category_name IS NULL'); } catch (e) { /* ignored */ }
          }

          if (oldVersion < 9) {
            // This migration ensures the items table exists for everyone.
            await db.execute('''
              CREATE TABLE IF NOT EXISTS $itemsTable (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                categoryId INTEGER NOT NULL,
                price REAL NOT NULL,
                imagePath TEXT,
                FOREIGN KEY (categoryId) REFERENCES categories(id) ON DELETE CASCADE
              )
            ''');
          }
        },
        onDowngrade: onDatabaseDowngradeDelete,
      );
    } catch (e) {
      debugPrint('Error initializing database: $e');
      rethrow;
    }
  }

  // CRUD Operations for Categories

  /// Insert a new category
  Future<int> insertCategory(String name, int color, {String? imagePath}) async {
    final db = await database;
    final category = {
      'name': name,
      'color': color,
      'imagePath': imagePath,
    };
    debugPrint('Inserting category: name=$name, color=0x${color.toRadixString(16).toUpperCase()}, imagePath=$imagePath');
    return await db.insert(
      categoriesTable,
      category,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all categories
  Future<List<Category>> getCategories() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(categoriesTable);
    debugPrint('Retrieved ${maps.length} categories from database');
    return List.generate(maps.length, (i) {
      final map = maps[i];
      debugPrint('Raw category data: id=${map['id']}, name=${map['name']}, color=${map['color']} (${map['color'].runtimeType})');
      final category = Category.fromMap(map);
      debugPrint('Parsed category: id=${category.id}, name=${category.name}, color=0x${category.color.value.toRadixString(16).toUpperCase()}');
      return category;
    });
  }

  /// Update an existing category
  Future<int> updateCategory(int id, String name, int color, {String? imagePath}) async {
    final db = await database;
    final category = {
      'name': name,
      'color': color,
      'imagePath': imagePath,
    };
    debugPrint('Updating category $id: name=$name, color=0x${color.toRadixString(16).toUpperCase()}, imagePath=$imagePath');
    return await db.update(
      categoriesTable,
      category,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete a category
  Future<int> deleteCategory(int id) async {
    final db = await database;
    return await db.delete(
      categoriesTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get a specific category by ID
  Future<Category?> getCategoryById(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      categoriesTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return Category.fromMap(maps.first);
    }
    return null;
  }

  /// Ensures a category with the given name exists, creating it if it doesn't.
  /// Returns the existing or newly created category.
  Future<Category> ensureCategoryExists(String name, Color color) async {
    final db = await database;
    // Case-insensitive search for the category
    final List<Map<String, dynamic>> maps = await db.query(
      categoriesTable,
      where: 'LOWER(name) = ?',
      whereArgs: [name.toLowerCase()],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      // Category already exists, return it
      return Category.fromMap(maps.first);
    } else {
      // Category does not exist, create it
      final newCategory = Category(name: name, color: color);
      final id = await db.insert(categoriesTable, {
        'name': newCategory.name,
        'color': newCategory.color.value,
        'imagePath': newCategory.imagePath,
      });
      return Category(id: id, name: name, color: color);
    }
  }

  // --- CRUD Operations for Pre-defined Items ---

  /// Insert a new pre-defined item
  Future<int> insertItem(Item item) async {
    final db = await database;
    return await db.insert(itemsTable, item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Get all pre-defined items
  Future<List<Item>> getItems() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(itemsTable);
    debugPrint('Retrieved ${maps.length} pre-defined items from the database.');
    return List.generate(maps.length, (i) {
      return Item.fromMap(maps[i]);
    });
  }

  /// Delete a pre-defined item
  Future<int> deleteItem(int id) async {
    final db = await database;
    return await db.delete(
      itemsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Update an existing pre-defined item
  Future<int> updateItem(Item item) async {
    final db = await database;
    return await db.update(
      itemsTable,
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  // --- CRUD Operations for Bought Items ---

  /// Save a list of bought items to the database
  Future<void> saveBoughtItems(List<Map<String, dynamic>> items) async {
    final db = await database;
    final batch = db.batch();
    for (final item in items) {
      final currentTime = item['date'] ?? DateTime.now().millisecondsSinceEpoch;
      // This map needs to match the new bought_items schema
      final itemData = {
        'name': item['name'],
        'quantity': item['quantity'],
        'unit': item['unit'],
        'price': item['price'],
        'category_name': item['category'], // New field for aligned schema
        'category_id': item['categoryId'], // New field for aligned schema
        'status': 1, // 1 for bought
        'date': currentTime,
        'categoryColor': item['categoryColor'],
        'unitPrice': item['unitPrice'],
        'imagePath': item['imagePath'],
        // Legacy columns that might have NOT NULL constraints on older DB versions.
        // Providing values for them ensures backward compatibility.
        'category': item['category'],
        'boughtTime': currentTime,
      };
      batch.insert(boughtItemsTable, itemData,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Get all bought items, ordered by date
  Future<List<Map<String, dynamic>>> getBoughtItems() async {
    final db = await database;
    return await db.query(boughtItemsTable, orderBy: 'date DESC');
  }

  /// Update an existing bought item
  Future<int> updateBoughtItem(int id, Map<String, dynamic> itemData) async {
    final db = await database;
    // The incoming map from bought_item.dart should be correct, but let's ensure it maps to the DB schema
    final dataToUpdate = {
      'name': itemData['name'],
      'quantity': itemData['quantity'],
      'unit': itemData['unit'],
      'price': itemData['price'],
      'category_name': itemData['category_name'],
      'category_id': itemData['category_id'],
      'date': itemData['date'],
      'categoryColor': itemData['categoryColor'],
      'unitPrice': itemData['unitPrice'],
      'imagePath': itemData['imagePath'],
    };
    return await db.update(
      boughtItemsTable,
      dataToUpdate,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete one or more bought items
  Future<int> deleteBoughtItems(List<int> ids) async {
    final db = await database;
    return await db.delete(
      boughtItemsTable,
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }

  /// Clear all bought items from the database
  Future<void> clearBoughtItems() async {
    final db = await database;
    await db.delete(boughtItemsTable);
  }

  // --- Reporting Methods for Bought Items ---

  /// Get bought items by a specific date
  Future<List<Map<String, dynamic>>> getBoughtItemsByDate(DateTime date) async {
    final db = await database;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return await db.query(
      boughtItemsTable, // Corrected table name
      where: 'date BETWEEN ? AND ?', // Corrected column name
      whereArgs: [
        startOfDay.millisecondsSinceEpoch,
        endOfDay.millisecondsSinceEpoch,
      ],
      orderBy: 'date DESC',
    );
  }

  /// Get bought items by date range
  Future<List<Map<String, dynamic>>> getBoughtItemsByDateRange(
    DateTime fromDateTime,
    DateTime toDateTime,
  ) async {
    final db = await database;
    return await db.query(
      boughtItemsTable, // Corrected table name
      where: 'date BETWEEN ? AND ?', // Corrected column name
      whereArgs: [
        fromDateTime.millisecondsSinceEpoch,
        toDateTime.millisecondsSinceEpoch,
      ],
      orderBy: 'date DESC',
    );
  }

  /// Get total spending by date range
  Future<double> getTotalSpendingByDateRange(
    DateTime fromDateTime,
    DateTime toDateTime,
  ) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT SUM(price) as total
      FROM $boughtItemsTable
      WHERE date BETWEEN ? AND ?
    ''', [fromDateTime.millisecondsSinceEpoch, toDateTime.millisecondsSinceEpoch]);
    return result.first['total'] as double? ?? 0.0;
  }

  /// Get total spending by category in a date range
  Future<List<Map<String, dynamic>>> getTotalSpendingByCategory(
    DateTime fromDateTime,
    DateTime toDateTime,
  ) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT 
        category_name,
        categoryColor,
        SUM(price) as total
      FROM $boughtItemsTable
      WHERE date BETWEEN ? AND ?
      GROUP BY category_id
      ORDER BY total DESC
    ''', [fromDateTime.millisecondsSinceEpoch, toDateTime.millisecondsSinceEpoch]);
  }

  /// Get all unique image paths from all tables
  Future<List<String>> getAllImagePaths() async {
    final db = await database;
    final List<String> paths = [];

    // Helper to query and add paths
    Future<void> queryAndAddPaths(String table, String column) async {
      try {
        final List<Map<String, dynamic>> maps = await db.query(table, columns: [column]);
        for (var map in maps) {
          final path = map[column] as String?;
          if (path != null && path.isNotEmpty) {
            paths.add(path);
          }
        }
      } catch (e) {
        // Ignore if table or column doesn't exist for some reason
        print('Could not query image paths from $table: $e');
      }
    }

    await queryAndAddPaths(categoriesTable, 'imagePath');
    await queryAndAddPaths(itemsTable, 'imagePath');
    await queryAndAddPaths(boughtItemsTable, 'imagePath');

    return paths.toSet().toList(); // Return unique paths
  }
}
