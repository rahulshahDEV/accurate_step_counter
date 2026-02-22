/// Runtime state of the step counter engine.
///
/// This is used to make lifecycle transitions explicit and testable.
enum StepRuntimeState {
  /// Instance created but no storage/detector setup started yet.
  uninitialized,

  /// Storage/runtime components are being initialized.
  initializing,

  /// Storage is ready and instance is idle.
  initialized,

  /// Detector start sequence is in progress.
  starting,

  /// Active detection while app is foregrounded.
  detectingForeground,

  /// Active detection while app is backgrounded/paused.
  detectingBackground,

  /// Terminated-state reconciliation is in progress.
  recoveringAfterTermination,

  /// Stop sequence is in progress.
  stopping,

  /// Fully stopped.
  stopped,

  /// Entered when a recoverable runtime error occurs.
  error,
}
