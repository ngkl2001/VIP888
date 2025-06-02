class OptimisticStateManager {
  final Set<String> _pending = {};
  final Set<String> _deleted = {};
  final Set<String> _added = {};

  void markPending(String ts) => _pending.add(ts);
  void markDeleted(String ts) => _deleted.add(ts);
  void markAdded(String ts) => _added.add(ts);
  
  void clear(String ts) {
    _pending.remove(ts);
    _deleted.remove(ts);
    _added.remove(ts);
  }

  bool isPending(String ts) => _pending.contains(ts);
  bool isDeleted(String ts) => _deleted.contains(ts);
  bool isAdded(String ts) => _added.contains(ts);

  bool get hasPendingOperations => _pending.isNotEmpty;
  bool get hasPendingDeletes => _deleted.isNotEmpty;
  bool get hasPendingAdds => _added.isNotEmpty;

  void clearAll() {
    _pending.clear();
    _deleted.clear();
    _added.clear();
  }
} 