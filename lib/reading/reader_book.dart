class PickedLocalBook {
  const PickedLocalBook({required this.name, required this.bytes});

  final String name;
  final List<int> bytes;
}

class ReaderBookSummary {
  const ReaderBookSummary({
    required this.id,
    required this.title,
    required this.place,
  });

  final String id;
  final String title;
  final int place;
}

class ReaderBook {
  const ReaderBook({
    required this.id,
    required this.title,
    required this.text,
    required this.place,
  });

  final String id;
  final String title;
  final String text;
  final int place;
}
