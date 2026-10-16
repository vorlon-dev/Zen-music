// ZenMusic Desktop — EQ parameter models (Android session EQ).
// ZenMusic remains GPL-3.0.

class EqBand {
  const EqBand({required this.centerHz, required this.gain});
  final double centerHz;
  final double gain;
}

class EqParams {
  const EqParams({
    required this.minDb,
    required this.maxDb,
    required this.bands,
  });
  final double minDb;
  final double maxDb;
  final List<EqBand> bands;
}
