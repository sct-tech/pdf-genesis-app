/// One tile of the page organiser. The id keeps selection and drag state
/// attached to the tile when pages are reordered, rotated or duplicated.
class PageEntry<T> {
  const PageEntry(this.id, this.page);

  final int id;
  final T page;
}

/// The order, rotation and selection of pages being organised.
///
/// Generic over the page type so the rules can be tested without opening a
/// PDF; the screen uses it with pdfrx pages.
class PageArrangement<T> {
  PageArrangement(
    Iterable<T> pages, {
    required this.maxPages,
    required this._rotate,
  }) {
    _entries.addAll(pages.map(_entry));
  }

  /// The most pages a document may have.
  final int maxPages;
  final T Function(T page) _rotate;

  final _entries = <PageEntry<T>>[];
  final _selected = <int>{};
  var _nextId = 0;
  var _changed = false;

  List<PageEntry<T>> get entries => List.unmodifiable(_entries);

  /// The pages in their current order, ready to be saved.
  List<T> get pages => [for (final entry in _entries) entry.page];

  int get length => _entries.length;
  int get selectedCount => _selected.length;
  bool get hasSelection => _selected.isNotEmpty;

  /// Whether anything differs from the document that was opened.
  bool get isChanged => _changed;

  bool isSelected(int id) => _selected.contains(id);

  PageEntry<T> _entry(T page) => PageEntry(_nextId++, page);

  void toggle(int id) {
    if (!_selected.remove(id)) _selected.add(id);
  }

  /// Moves the entry [id] to where [targetId] is, shifting the pages in
  /// between by one. Returns false when nothing moved.
  bool move(int id, {required int targetId}) {
    final from = _entries.indexWhere((entry) => entry.id == id);
    final to = _entries.indexWhere((entry) => entry.id == targetId);
    if (from < 0 || to < 0 || from == to) return false;
    _entries.insert(to, _entries.removeAt(from));
    _changed = true;
    return true;
  }

  /// Turns each selected page a quarter turn clockwise.
  void rotateSelected() {
    if (!hasSelection) return;
    for (var i = 0; i < _entries.length; i++) {
      final entry = _entries[i];
      if (_selected.contains(entry.id)) {
        _entries[i] = PageEntry(entry.id, _rotate(entry.page));
      }
    }
    _changed = true;
  }

  /// Puts a copy of each selected page right after it. Returns false, and
  /// changes nothing, when that would exceed [maxPages].
  bool duplicateSelected() {
    if (!hasSelection) return true;
    if (_entries.length + _selected.length > maxPages) return false;
    for (var i = _entries.length - 1; i >= 0; i--) {
      if (_selected.contains(_entries[i].id)) {
        _entries.insert(i + 1, _entry(_entries[i].page));
      }
    }
    _changed = true;
    return true;
  }

  /// Removes the selected pages. Returns false, and changes nothing, when
  /// that would leave no pages at all.
  bool deleteSelected() {
    if (!hasSelection) return true;
    if (_selected.length >= _entries.length) return false;
    _entries.removeWhere((entry) => _selected.contains(entry.id));
    _selected.clear();
    _changed = true;
    return true;
  }

  /// Appends [pages]. Returns false, and changes nothing, when that would
  /// exceed [maxPages].
  bool append(List<T> pages) {
    if (_entries.length + pages.length > maxPages) return false;
    _entries.addAll(pages.map(_entry));
    _changed = true;
    return true;
  }
}
