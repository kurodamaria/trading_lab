class Candle {
  final int index;
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  const Candle({
    required this.index,
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume = 0.0,
  });
}
