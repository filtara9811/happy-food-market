import 'models.dart';

/// Same example data as the prototype, so screens can be compared side by side.
class Demo {
  static final rider = Rider(name: 'Rohit Kumar', phone: '+91 98765 43210', bike: 'DL 3S AB 4821', rating: 4.9, trips: 1284, online: true, autoAccept: false, cash: 640);

  static final stock = <StockLine>[
    StockLine('स्टीम मोमोज़', '🥟', 99, 8),
    StockLine('वीआईपी शाही थाली', '🍱', 149, 6),
    StockLine('मटन रोगन जोश', '🍛', 179, 4),
    StockLine('ग्रिल्ड मसाला फिश', '🐟', 159, 3),
    StockLine('तंदूरी टिक्का प्लैटर', '🍢', 249, 2),
    StockLine('बीबीक्यू चिकन सीख', '🍗', 189, 5),
    StockLine('पानी पूरी प्लैटर', '🥙', 139, 5),
    StockLine('दही पापड़ी चाट', '🥗', 119, 4),
  ];

  static DateTime at(int h, int m) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day, h, m);
  }

  static List<JStep> _tl(DateTime start, List<List<Object>> s) {
    var t = start;
    return s.map((x) {
      t = t.add(Duration(minutes: x[3] as int));
      return JStep(x[0] as String, x[1] as String, x[2] as String, t);
    }).toList();
  }

  static final jobs = <Job>[
    Job(id: 'J-C1', kind: Kind.counter, customer: 'काउंटर ग्राहक', pay: 'UPI', done: true, earn: 0, at: at(13, 5), example: true,
        items: const [Item('वीआईपी शाही थाली', '🍱', 2, 149), Item('शाही गुलाब जामुन', '🍮', 1, 69)],
        steps: _tl(at(13, 5), [
          ['🛒', 'ग्राहक बाइक पर आया', '“2 थाली और जामुन दे दो”', 0],
          ['📷', 'सामान स्कैन / चुना', 'टोकरी के स्टॉक से', 1],
          ['🧾', 'बिल बना', 'HFR-0012', 1],
          ['💳', 'पैसे मिले', 'UPI से तुरंत', 1],
          ['📦', 'स्टॉक घटा', 'थाली 6 → 4, जामुन 8 → 7', 0],
        ])),
    Job(id: 'J-S1', kind: Kind.stock, customer: 'Kavita Sharma', pay: 'कैश', done: true, earn: 35, at: at(12, 20), rating: 5, review: '5 मिनट में गरम-गरम मिला 😍', example: true,
        items: const [Item('स्टीम मोमोज़', '🥟', 2, 99)],
        steps: _tl(at(12, 20), [
          ['🔔', 'रिक्वेस्ट आई', 'ग्राहक 600 मीटर दूर • मोमोज़ आपकी टोकरी में हैं', 0],
          ['✅', 'आपने स्वीकार किया', '8 सेकंड में', 0],
          ['🛵', 'निकल गए', 'सीधे टोकरी से — दुकान नहीं जाना', 1],
          ['🔑', 'OTP से डिलीवर', 'OTP 4821', 4],
          ['💵', 'कैश लिया', '₹198', 0],
          ['⭐', 'ग्राहक ने रेटिंग दी', '⭐⭐⭐⭐⭐', 2],
        ])),
    Job(id: 'J-V1', kind: Kind.vendor, customer: 'Rahul Singh', pay: 'UPI', done: true, earn: 25, at: at(11, 0), rating: 4, review: 'खाना बढ़िया, थोड़ी देर हुई', example: true,
        items: const [Item('मटन रोगन जोश', '🍛', 1, 179), Item('पानी पूरी प्लैटर', '🥙', 1, 139)],
        steps: _tl(at(11, 0), [
          ['🔔', 'रिक्वेस्ट आई', 'किसी राइडर की टोकरी में पूरा सामान नहीं था', 0],
          ['🏪', 'दुकान को गई', 'Happy Food Kitchen • 1.2 km', 0],
          ['✅', 'दुकान ने माना', '40 सेकंड में', 1],
          ['👨‍🍳', 'पैक हुआ', '12 मिनट में', 12],
          ['🛵', 'आपको मिला', 'सबसे पास वाले राइडर', 0],
          ['📍', 'दुकान पहुँचे', '4 मिनट में', 4],
          ['🛍️', 'पिकअप किया', 'पैकेट गिनकर', 1],
          ['🛵', 'रास्ते में', '2.1 km', 0],
          ['🏠', 'डिलीवर', 'OTP 3307', 9],
          ['⭐', 'ग्राहक ने रेटिंग दी', '⭐⭐⭐⭐', 3],
        ])),
    Job(id: 'O-1', kind: Kind.stock, customer: 'Anita Verma', pay: 'कैश', done: true, earn: 25, at: at(9, 12), items: const [Item('बीबीक्यू चिकन सीख', '🍗', 1, 189)],
        steps: _tl(at(9, 12), [['✅', 'स्वीकार', '', 0], ['📦', 'टोकरी से', '', 0], ['🛵', 'रास्ते में', '', 2], ['🏠', 'डिलीवर', '', 6], ['💵', 'कैश लिया', '₹189', 0]])),
    Job(id: 'O-2', kind: Kind.stock, customer: 'Sanjay Gupta', pay: 'कैश', done: true, earn: 25, at: at(10, 50), items: const [Item('मटन रोगन जोश', '🍛', 2, 179)],
        steps: _tl(at(10, 50), [['✅', 'स्वीकार', '', 0], ['📦', 'टोकरी से', '', 0], ['🛵', 'रास्ते में', '', 2], ['🏠', 'डिलीवर', '', 7], ['💵', 'कैश लिया', '₹358', 0]])),
  ];

  /// [earnings, deliveries] per day for the day strip (today first), like the prototype.
  static const days = <List<int>>[
    [150, 6], [75, 3], [50, 3], [50, 3], [50, 2], [25, 1],
  ];
}
