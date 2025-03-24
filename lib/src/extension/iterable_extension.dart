/// double型のリストに対する拡張機能
extension ListExtension on List<double> {
  /// リストの中央の要素のインデックスを取得する
  ///
  /// 奇数長のリストの場合は真ん中のインデックス、
  /// 偶数長のリストの場合は中央より左側のインデックスを返す
  ///
  /// リストが空の場合は0を返す
  int getCenterIndex() {
    if (isEmpty) {
      return 0;
    }
    int centerIndex = length ~/ 2;
    final result = length.isOdd ? centerIndex : centerIndex - 1;
    return result;
  }
}
