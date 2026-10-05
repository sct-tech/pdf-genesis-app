import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color, Offset;

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart';
import 'package:pdfrx/pdfrx.dart';

import 'edit_marks.dart';
import 'text_rasteriser.dart';

/// Thrown when PDFium refuses part of an edit. Nothing is saved in that
/// case: a PDF with some of the user's marks missing must never be stored
/// as if the save had worked.
class PdfWriteException implements Exception {
  const PdfWriteException(this.step);

  /// The PDFium call that failed, for logs.
  final String step;

  @override
  String toString() => 'PdfWriteException: $step';
}

typedef _WriteJob = ({
  int document,
  List<EditMark> marks,
  double baselineRatio,

  /// Notes that are placed as images, by mark id.
  Map<int, RasterisedText> rasters,
});

/// Writes [EditMark]s into a PDF as real page content, so they show in every
/// PDF reader, and returns the new file.
///
/// pdfrx has no API for adding content, so this talks to PDFium directly
/// through the handle pdfrx exposes.
class PdfMarkWriter {
  const PdfMarkWriter._();

  /// [baselineRatio] is the distance from the top of a text line to its
  /// baseline, as a multiple of the font size, measured by the editor so the
  /// saved text lands where the preview showed it.
  ///
  /// Throws [PdfWriteException] when any mark could not be written.
  static Future<Uint8List> apply({
    required String path,
    required List<EditMark> marks,
    required double baselineRatio,
  }) async {
    await pdfrxFlutterInitialize();
    // Drawn here: the worker isolate has no text layout
    final rasters = <int, RasterisedText>{
      for (final mark in marks)
        if (mark is TextMark && !mark.isSelectableInPdf)
          mark.id: await rasteriseText(mark),
    };
    final document = await PdfDocument.openFile(path);
    try {
      // The handle is only meant to be used inside this callback. Taking it
      // out is safe here because the document is private to this method and
      // stays open until the edit below has finished.
      final handle = await document.useNativeDocumentHandle((handle) => handle);
      // PDFium calls back into pdfrx (font lookup, file reads) through
      // callbacks bound to pdfrx's worker isolate, so the edit runs there.
      try {
        await PdfrxEntryFunctions.instance.compute(_write, (
          document: handle,
          marks: marks,
          baselineRatio: baselineRatio,
          rasters: rasters,
        ));
      } on Object catch (error) {
        // pdfrx passes a worker failure back as its own private type, with
        // the original error only as text
        throw PdfWriteException('$error');
      }
      return await document.encodePdf();
    } finally {
      await document.dispose();
    }
  }

  /// Runs in the worker isolate: must not touch anything but its argument.
  static void _write(_WriteJob job) {
    final byPage = <int, List<EditMark>>{};
    for (final mark in job.marks) {
      byPage.putIfAbsent(mark.page, () => []).add(mark);
    }
    using((arena) {
      final writer = _PageWriter(
        // The worker sets the module path up before it runs any job
        pdfium: getPdfium(modulePath: Pdfrx.pdfiumModulePath),
        document: FPDF_DOCUMENT.fromAddress(job.document),
        arena: arena,
        job: job,
      );
      byPage.forEach(writer.writePage);
    });
  }
}

/// Adds marks to one page at a time. Lives only inside the worker isolate.
class _PageWriter {
  _PageWriter({
    required this.pdfium,
    required this.document,
    required this.arena,
    required this.job,
  }) : _outX = arena<Double>(),
       _outY = arena<Double>(),
       _helvetica = 'Helvetica'.toNativeUtf8(allocator: arena).cast<Char>(),
       _multiply = 'Multiply'.toNativeUtf8(allocator: arena).cast<Char>();

  // The virtual canvas FPDF_DeviceToPage maps from. It only takes whole
  // pixels, so the canvas is large enough to keep the rounding invisible.
  static const _canvasLongSide = 20000;

  static const _roundCap = 1;
  static const _roundJoin = 1;

  final PDFium pdfium;
  final FPDF_DOCUMENT document;
  final Arena arena;
  final _WriteJob job;

  final Pointer<Double> _outX;
  final Pointer<Double> _outY;
  final Pointer<Char> _helvetica;
  final Pointer<Char> _multiply;

  // The page being written
  late FPDF_PAGE _page;
  late double _width;
  late double _height;
  late int _canvasWidth;
  late int _canvasHeight;

  void writePage(int pageNumber, List<EditMark> marks) {
    _page = pdfium.FPDF_LoadPage(document, pageNumber - 1);
    if (_page == nullptr) throw PdfWriteException('FPDF_LoadPage($pageNumber)');
    try {
      // Displayed size in points, with the page's own rotation applied
      _width = pdfium.FPDF_GetPageWidthF(_page);
      _height = pdfium.FPDF_GetPageHeightF(_page);
      final scale = _canvasLongSide / math.max(_width, _height);
      _canvasWidth = (_width * scale).round();
      _canvasHeight = (_height * scale).round();

      for (final mark in marks) {
        switch (mark) {
          case StrokeMark():
            _addStroke(
              mark.points,
              mark.color,
              mark.width * _width,
              highlighter: mark.highlighter,
            );
          case TextMark():
            final raster = job.rasters[mark.id];
            raster == null ? _addText(mark) : _addImage(raster);
          case SignatureMark(:final rect):
            for (final stroke in mark.signature.strokes) {
              _addStroke(
                [
                  for (final point in stroke)
                    Offset(
                      rect.left + point.dx * rect.width,
                      rect.top + point.dy * rect.height,
                    ),
                ],
                mark.color,
                signatureStrokeWidth * rect.width * _width,
              );
            }
        }
      }
      _check(
        pdfium.FPDFPage_GenerateContent(_page),
        'FPDFPage_GenerateContent',
      );
    } finally {
      pdfium.FPDF_ClosePage(_page);
    }
  }

  void _check(int result, String step) {
    if (result == 0) throw PdfWriteException(step);
  }

  T _created<T extends Pointer>(T object, String step) {
    if (object == nullptr) throw PdfWriteException(step);
    return object;
  }

  /// Hands [object] to the page, which owns it from here on.
  void _insert(FPDF_PAGEOBJECT object) => _check(
    pdfium.FPDFPage_InsertObject(_page, object),
    'FPDFPage_InsertObject',
  );

  /// Normalised display position -> PDF user space. PDFium accounts for
  /// page rotation and the crop box.
  Offset _toPage(Offset point) {
    pdfium.FPDF_DeviceToPage(
      _page,
      0,
      0,
      _canvasWidth,
      _canvasHeight,
      0,
      (point.dx * _canvasWidth).round(),
      (point.dy * _canvasHeight).round(),
      _outX,
      _outY,
    );
    return Offset(_outX.value, _outY.value);
  }

  void _addStroke(
    List<Offset> points,
    Color color,
    double widthPt, {
    bool highlighter = false,
  }) {
    if (points.isEmpty) return;
    final start = _toPage(points.first);
    final path = _created(
      pdfium.FPDFPageObj_CreateNewPath(start.dx, start.dy),
      'FPDFPageObj_CreateNewPath',
    );
    // A tap leaves one point; a zero-length line with round caps draws it
    // as a dot
    for (final point in points.length == 1 ? points : points.skip(1)) {
      final next = _toPage(point);
      pdfium.FPDFPath_LineTo(path, next.dx, next.dy);
    }
    pdfium
      ..FPDFPath_SetDrawMode(path, 0, 1)
      ..FPDFPageObj_SetStrokeColor(
        path,
        _channel(color.r),
        _channel(color.g),
        _channel(color.b),
        _channel(color.a),
      )
      ..FPDFPageObj_SetStrokeWidth(path, widthPt)
      ..FPDFPageObj_SetLineCap(path, _roundCap)
      ..FPDFPageObj_SetLineJoin(path, _roundJoin);
    if (highlighter) pdfium.FPDFPageObj_SetBlendMode(path, _multiply);
    _insert(path);
  }

  /// Writes a note as real text in the standard Helvetica font.
  void _addText(TextMark mark) {
    final fontSize = mark.size * _width;
    // Unit vectors of "right" and "up" on screen, in user space, so the
    // text reads upright on rotated pages too
    final origin = _toPage(mark.position);
    final right = _unit(_toPage(mark.position.translate(0.1, 0)) - origin);
    final up = _unit(_toPage(mark.position.translate(0, -0.1)) - origin);

    final lines = mark.pdfText.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      final baseline = _toPage(
        mark.position.translate(
          0,
          (i * TextMark.lineHeight + job.baselineRatio) * fontSize / _height,
        ),
      );
      final text = _created(
        pdfium.FPDFPageObj_NewTextObj(document, _helvetica, fontSize),
        'FPDFPageObj_NewTextObj',
      );
      _check(
        pdfium.FPDFText_SetText(
          text,
          lines[i].toNativeUtf16(allocator: arena).cast<FPDF_WCHAR>(),
        ),
        'FPDFText_SetText',
      );
      pdfium
        ..FPDFPageObj_SetFillColor(
          text,
          _channel(mark.color.r),
          _channel(mark.color.g),
          _channel(mark.color.b),
          255,
        )
        ..FPDFPageObj_Transform(
          text,
          right.dx,
          right.dy,
          up.dx,
          up.dy,
          baseline.dx,
          baseline.dy,
        );
      _insert(text);
    }
  }

  /// Places a note that was drawn to pixels.
  void _addImage(RasterisedText raster) {
    // The image's unit square is mapped onto the note's box, corner by
    // corner, which also turns it upright on rotated pages
    final bottomLeft = _toPage(raster.bounds.bottomLeft);
    final across = _toPage(raster.bounds.bottomRight) - bottomLeft;
    final upward = _toPage(raster.bounds.topLeft) - bottomLeft;

    final bitmap = _created(
      pdfium.FPDFBitmap_CreateEx(
        raster.width,
        raster.height,
        FPDFBitmap_BGRA,
        nullptr,
        0,
      ),
      'FPDFBitmap_CreateEx',
    );
    try {
      final stride = pdfium.FPDFBitmap_GetStride(bitmap);
      final rowBytes = raster.width * 4;
      final buffer = pdfium.FPDFBitmap_GetBuffer(bitmap)
          .cast<Uint8>()
          .asTypedList(stride * raster.height);
      for (var row = 0; row < raster.height; row++) {
        buffer.setRange(
          row * stride,
          row * stride + rowBytes,
          raster.bgra,
          row * rowBytes,
        );
      }
      final image = _created(
        pdfium.FPDFPageObj_NewImageObj(document),
        'FPDFPageObj_NewImageObj',
      );
      _check(
        pdfium.FPDFImageObj_SetBitmap(nullptr, 0, image, bitmap),
        'FPDFImageObj_SetBitmap',
      );
      _check(
        pdfium.FPDFImageObj_SetMatrix(
          image,
          across.dx,
          across.dy,
          upward.dx,
          upward.dy,
          bottomLeft.dx,
          bottomLeft.dy,
        ),
        'FPDFImageObj_SetMatrix',
      );
      _insert(image);
    } finally {
      // PDFium copied the pixels into the image object
      pdfium.FPDFBitmap_Destroy(bitmap);
    }
  }

  static int _channel(double value) => (value * 255).round().clamp(0, 255);

  static Offset _unit(Offset vector) {
    final length = vector.distance;
    return length == 0 ? vector : vector / length;
  }
}
