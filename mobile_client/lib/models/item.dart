class Item {
  final int id;
  final String name;
  final double price;

  const Item({required this.id, required this.name, required this.price});

  factory Item.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final price = json['price'];
    if (id is! int || name is! String || price is! num ||
        name.trim().isEmpty || !price.toDouble().isFinite || price < 0) {
      throw const FormatException('Invalid item fields');
    }
    return Item(id: id, name: name, price: price.toDouble());
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'price': price};
}
