import 'dart:async';

import '../lib/week6/item.dart';
import '../lib/week6/item_repository.dart';

const sampleItems = [
  Item(id: 1, name: 'Item 1', description: 'fresh local'),
  Item(id: 2, name: 'Item 2', description: 'spicy golden'),
];

/// Returns fixed data at once (success state).
class FakeRepo implements ItemRepository {
  FakeRepo([this.items = sampleItems]);
  final List<Item> items;

  @override
  Future<List<Item>> fetchItems() async => items;

  @override
  Future<Item> fetchItem(int id) async => items.firstWhere((i) => i.id == id);
}

/// Always fails (error state).
class FailingRepo implements ItemRepository {
  @override
  Future<List<Item>> fetchItems() async =>
      throw const ApiException('HTTP 500', statusCode: 500);

  @override
  Future<Item> fetchItem(int id) async =>
      throw const ApiException('HTTP 500', statusCode: 500);
}

/// Never answers until the test completes the completer (loading state,
/// and "the response arrives after the user left" in Part 2).
class SlowRepo implements ItemRepository {
  final itemsCompleter = Completer<List<Item>>();
  final itemCompleter = Completer<Item>();

  @override
  Future<List<Item>> fetchItems() => itemsCompleter.future;

  @override
  Future<Item> fetchItem(int id) => itemCompleter.future;
}
