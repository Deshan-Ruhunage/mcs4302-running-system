import 'dart:convert';
import 'dart:isolate';

class Item {
  const Item({
    required this.id,
    required this.name,
    this.description = '',
    this.price = 0,
    this.tags = const [],
  });

  final int id;
  final String name;
  final String description;
  final double price;
  final List<String> tags;

  factory Item.fromJson(Map<String, dynamic> json) => Item(
        id: json['id'] as int,
        name: json['name'] as String,
        description: (json['description'] as String?) ?? '',
        price: (json['price'] as num?)?.toDouble() ?? 0,
        tags: List<String>.from((json['tags'] as List?) ?? const []),
      );
}

/// Synchronous: parses on whichever isolate calls it.
List<Item> decodeItems(String body) {
  final data = jsonDecode(body);
  if (data is! List) {
    throw const FormatException('Expected a JSON list of items');
  }
  return [for (final e in data) Item.fromJson(e as Map<String, dynamic>)];
}

/// Parses on a short-lived worker isolate. Top-level on purpose: the
/// closure then captures only [body], which can be sent to the worker.
Future<List<Item>> decodeItemsInIsolate(String body) =>
    Isolate.run(() => decodeItems(body));
