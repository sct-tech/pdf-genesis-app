import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_genesis/features/viewer/application/page_arrangement.dart';

void main() {
  // Pages are letters; rotating one adds a tick so it can be told apart
  PageArrangement<String> arrangement(String pages, {int maxPages = 10}) =>
      PageArrangement(
        pages.split(''),
        maxPages: maxPages,
        rotate: (page) => "$page'",
      );

  int idOf(PageArrangement<String> pages, String page) =>
      pages.entries.firstWhere((entry) => entry.page == page).id;

  test('starts unchanged, in the order of the document', () {
    final pages = arrangement('ABC');

    expect(pages.pages, ['A', 'B', 'C']);
    expect(pages.isChanged, isFalse);
    expect(pages.hasSelection, isFalse);
  });

  test('moving a page later shifts the pages in between forward', () {
    final pages = arrangement('ABCD');

    final moved = pages.move(idOf(pages, 'A'), targetId: idOf(pages, 'C'));

    expect(moved, isTrue);
    expect(pages.pages, ['B', 'C', 'A', 'D']);
    expect(pages.isChanged, isTrue);
  });

  test('moving a page earlier shifts the pages in between back', () {
    final pages = arrangement('ABCD');

    pages.move(idOf(pages, 'D'), targetId: idOf(pages, 'B'));

    expect(pages.pages, ['A', 'D', 'B', 'C']);
  });

  test('dropping a page on itself changes nothing', () {
    final pages = arrangement('ABC');

    final moved = pages.move(idOf(pages, 'B'), targetId: idOf(pages, 'B'));

    expect(moved, isFalse);
    expect(pages.isChanged, isFalse);
  });

  test('rotating affects only the selection and keeps it selected', () {
    final pages = arrangement('ABC');
    final id = idOf(pages, 'B');
    pages
      ..toggle(id)
      ..rotateSelected();

    expect(pages.pages, ['A', "B'", 'C']);
    expect(pages.isSelected(id), isTrue);

    pages.rotateSelected();
    expect(pages.pages, ['A', "B''", 'C']);
  });

  test('a duplicate goes right after its original and is not selected', () {
    final pages = arrangement('ABC');
    pages
      ..toggle(idOf(pages, 'A'))
      ..toggle(idOf(pages, 'C'));

    expect(pages.duplicateSelected(), isTrue);

    expect(pages.pages, ['A', 'A', 'B', 'C', 'C']);
    expect(pages.selectedCount, 2);
  });

  test('duplicating past the page limit is refused', () {
    final pages = arrangement('ABC', maxPages: 4);
    pages
      ..toggle(idOf(pages, 'A'))
      ..toggle(idOf(pages, 'B'));

    expect(pages.duplicateSelected(), isFalse);

    expect(pages.pages, ['A', 'B', 'C']);
    expect(pages.isChanged, isFalse);
  });

  test('deleting removes the selection and clears it', () {
    final pages = arrangement('ABC');
    pages.toggle(idOf(pages, 'B'));

    expect(pages.deleteSelected(), isTrue);

    expect(pages.pages, ['A', 'C']);
    expect(pages.hasSelection, isFalse);
  });

  test('deleting every page is refused', () {
    final pages = arrangement('AB');
    pages
      ..toggle(idOf(pages, 'A'))
      ..toggle(idOf(pages, 'B'));

    expect(pages.deleteSelected(), isFalse);

    expect(pages.pages, ['A', 'B']);
  });

  test('pages from another PDF are appended up to the limit', () {
    final pages = arrangement('AB', maxPages: 4);

    expect(pages.append(['X', 'Y']), isTrue);
    expect(pages.pages, ['A', 'B', 'X', 'Y']);

    expect(pages.append(['Z']), isFalse);
    expect(pages.length, 4);
  });

  test('tapping a selected page deselects it', () {
    final pages = arrangement('AB');
    final id = idOf(pages, 'A');

    pages.toggle(id);
    expect(pages.isSelected(id), isTrue);

    pages.toggle(id);
    expect(pages.hasSelection, isFalse);
    // Selecting is not an edit
    expect(pages.isChanged, isFalse);
  });
}
