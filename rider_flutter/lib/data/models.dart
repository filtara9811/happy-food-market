/// Data shapes mirror the prototype (DB.riders / DB.orders / journeys).
class Item {
  final String name;
  final String emoji;
  final int qty;
  final int price;
  const Item(this.name, this.emoji, this.qty, this.price);
}

class JStep {
  final String icon;
  final String title;
  final String detail;
  final DateTime at;
  const JStep(this.icon, this.title, this.detail, this.at);
}

enum Kind { counter, stock, vendor, restock }

class Job {
  final String id;
  final Kind kind;
  final String customer;
  final List<Item> items;
  final DateTime at;
  final int earn;
  final bool done;
  final String pay;
  final List<JStep> steps;
  final int? rating;
  final String? review;
  final bool example;
  const Job({required this.id, required this.kind, required this.customer, required this.items, required this.at, required this.earn, required this.done, required this.pay, required this.steps, this.rating, this.review, this.example = false});
  int get total => items.fold(0, (s, i) => s + i.qty * i.price);
}

class StockLine {
  final String name;
  final String emoji;
  final int price;
  int qty;
  StockLine(this.name, this.emoji, this.price, this.qty);
}

class Rider {
  String name;
  String phone;
  String bike;
  double rating;
  int trips;
  bool online;
  bool autoAccept;
  int cash;
  Rider({required this.name, required this.phone, required this.bike, required this.rating, required this.trips, required this.online, required this.autoAccept, required this.cash});
  String get initials => name.split(' ').where((p) => p.isNotEmpty).take(2).map((p) => p[0]).join().toUpperCase();
}
