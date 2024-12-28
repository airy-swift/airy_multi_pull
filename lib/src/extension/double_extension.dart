extension ListDoubleExtension on List<double> {
  (int, double) closestValue(double value) {
    if (isEmpty) {
      throw ArgumentError('The list cannot be empty');
    }
    double minDiff = (value - this[0]).abs();
    double closestValue = this[0];
    int targetIndex = 0;
    for (int i = 1; i < length; i++) {
      double diff = (value - this[i]).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closestValue = this[i];
        targetIndex = i;
      }
    }
    return (targetIndex, closestValue);
  }
}
