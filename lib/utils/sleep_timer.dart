/// Lógica do timer de desligamento.
///
/// Volume alvo num passo do fade-out (de `originalVolume` até 0).
double fadeTargetVolume(double originalVolume, int step, int steps) {
  return (originalVolume * (step / steps)).clamp(0.0, 1.0).toDouble();
}