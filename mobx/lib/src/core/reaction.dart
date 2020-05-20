part of '../core.dart';

abstract class Reaction implements Derivation {
  bool get isDisposed;

  UnmodifiableSetView<Atom> get observables;

  void dispose();

  void _run();
}

typedef ObservedAtomChangedListener = void Function(Reaction, Atom);

class ReactionImpl implements Reaction {
  ReactionImpl(
    this._context,
    Function() onInvalidate, {
    this.name,
    void Function(Object, Reaction) onError,
    void Function(Reaction, Atom) onObservedAtomChanged,
  })  : assert(_context != null),
        assert(onInvalidate != null) {
    _onInvalidate = onInvalidate;
    _onError = onError;
    _onObservedAtomChanged = onObservedAtomChanged;
  }

  void Function(Object, ReactionImpl) _onError;
  void Function(Reaction, Atom) _onObservedAtomChanged;

  final ReactiveContext _context;
  void Function() _onInvalidate;
  bool _isScheduled = false;
  bool _isDisposed = false;
  bool _isRunning = false;

  @override
  final String name;

  @override
  Set<Atom> _newObservables;

  @override
  // ignore: prefer_final_fields
  Set<Atom> _observables = {};

  @override
  UnmodifiableSetView<Atom> get observables =>
      UnmodifiableSetView(_observables);

  bool get hasObservables => _observables.isNotEmpty;

  @override
  // ignore: prefer_final_fields
  DerivationState _dependenciesState = DerivationState.notTracking;

  @override
  MobXCaughtException _errorValue;

  @override
  MobXCaughtException get errorValue => _errorValue;

  @override
  bool get isDisposed => _isDisposed;

  @override
  void _onBecomeStale({Atom changedAtom}) {
    if (_onObservedAtomChanged != null) {
      _onObservedAtomChanged(this, changedAtom);
    }
    schedule();
  }

  Derivation startTracking() {
    _context.startBatch();
    _isRunning = true;
    return _context._startTracking(this);
  }

  void endTracking(Derivation previous) {
    _context._endTracking(this, previous);
    _isRunning = false;

    if (_isDisposed) {
      _context._clearObservables(this);
    }

    _context.endBatch();
  }

  void track(void Function() fn) {
    _context.startBatch();

    _isRunning = true;
    _context.trackDerivation(this, fn);
    _isRunning = false;

    if (_isDisposed) {
      _context._clearObservables(this);
    }

    if (_context._hasCaughtException(this)) {
      _reportException(_errorValue._exception);
    }

    _context.endBatch();
  }

  @override
  void _run() {
    if (_isDisposed) {
      return;
    }

    _context.startBatch();

    _isScheduled = false;

    if (_context._shouldCompute(this)) {
      try {
        _onInvalidate();
      } on Object catch (e) {
        // Note: "on Object" accounts for both Error and Exception
        _errorValue = MobXCaughtException(e);
        if (_context.config.disableErrorBoundaries == true) {
          rethrow;
        } else {
          _reportException(e);
        }
      }
    }

    _context.endBatch();
  }

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;

    if (_isRunning) {
      return;
    }

    _context
      ..startBatch()
      .._clearObservables(this)
      ..endBatch();
  }

  void schedule() {
    if (_isScheduled) {
      return;
    }

    _isScheduled = true;
    _context
      ..addPendingReaction(this)
      ..runReactions();
  }

  @override
  // ignore: unused_element
  void _suspend() {
    // Not applicable right now
  }

  void _reportException(Object exception) {
    if (_onError != null) {
      _onError(exception, this);
      return;
    }

    if (_context.config.disableErrorBoundaries == true) {
      // ignore: only_throw_errors
      throw exception;
    }

    _context._notifyReactionErrorHandlers(exception, this);
  }

  @override
  String toString() => 'ReactionImpl: $name';
}
