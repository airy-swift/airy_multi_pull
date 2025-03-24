/// double型のリストに対する拡張機能
extension ListDoubleExtension on List<double> {
  /// リスト内で指定された値に最も近い値とそのインデックスを取得する
  ///
  /// [value] 比較する値
  ///
  /// 戻り値は (インデックス, 最も近い値) の形式のタプル
  ///
  /// リストが空の場合は例外をスローする
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
