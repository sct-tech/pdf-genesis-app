import 'dart:convert';
import 'dart:typed_data';

/// Builds a small text PDF with one line of text per page.
///
/// [rotation] sets the /Rotate entry of every page.
Uint8List buildSamplePdf(List<String> pageTexts, {int rotation = 0}) {
  final objects = <String>[];
  final kids = [for (var i = 0; i < pageTexts.length; i++) '${4 + i * 2} 0 R']
      .join(' ');
  objects
    ..add('<< /Type /Catalog /Pages 2 0 R >>')
    ..add('<< /Type /Pages /Kids [$kids] /Count ${pageTexts.length} >>')
    ..add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  for (var i = 0; i < pageTexts.length; i++) {
    final stream = 'BT /F1 12 Tf 72 720 Td (${pageTexts[i]}) Tj ET';
    objects
      ..add(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Rotate $rotation /Contents ${5 + i * 2} 0 R '
        '/Resources << /Font << /F1 3 0 R >> >> >>',
      )
      ..add('<< /Length ${stream.length} >>\nstream\n$stream\nendstream');
  }

  final body = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(body.length);
    body.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = body.length;
  body.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    body.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  body.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF',
  );
  return latin1.encode(body.toString());
}
