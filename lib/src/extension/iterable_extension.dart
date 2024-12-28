extension ListExtension on List<double> {
  int getCenterIndex() {
    if (isEmpty) {
      throw Exception("List is empty");
    }
    int centerIndex = length ~/ 2;
    final result = length.isOdd ? centerIndex : centerIndex - 1;
    return result;
  }
}
