/// The last confirmed reachability result, rather than the network interface.
enum InternetStatus {
  /// No successful check or confirmed failure has completed yet.
  unknown,

  /// At least one configured endpoint was reachable.
  online,

  /// The configured number of consecutive checks failed.
  offline,
}
