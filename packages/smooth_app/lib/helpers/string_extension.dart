extension StringExtension on String {
  String capitalize() => isEmpty ? this : this[0].toUpperCase() + substring(1);

  /// The first letter in capitals, for names shown in the app (17/11: every
  /// label starts with a capital). Names with their own capitals inside the
  /// first word ("iPhone", "eBay") are left as they are.
  String capFirst() {
    final String t = trimLeft();
    if (t.isEmpty) {
      return this;
    }
    final String first = t[0];
    if (first.toUpperCase() == first) {
      return this;
    }
    final String word = t.split(RegExp(r'\s')).first;
    if (word.substring(1) != word.substring(1).toLowerCase()) {
      return this;
    }
    return '${substring(0, length - t.length)}${first.toUpperCase()}${t.substring(1)}';
  }

  String removeSpaces() => replaceAll(RegExp(r' |\n|\r|\s|\t'), '');

  bool hasOnlyDigits() => int.tryParse(this) != null;
}
