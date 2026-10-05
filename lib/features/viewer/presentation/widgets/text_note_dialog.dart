import 'package:flutter/material.dart';

/// Asks for the text of a note. Resolves to the trimmed text, or null when
/// cancelled. An empty result means "remove the note".
Future<String?> showTextNoteDialog(
  BuildContext context, {
  String initial = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextNoteDialog(initial: initial),
  );
}

class _TextNoteDialog extends StatefulWidget {
  const _TextNoteDialog({required this.initial});

  final String initial;

  @override
  State<_TextNoteDialog> createState() => _TextNoteDialogState();
}

class _TextNoteDialogState extends State<_TextNoteDialog> {
  late final _field = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial.isEmpty ? 'Add text' : 'Edit text'),
      content: TextField(
        controller: _field,
        autofocus: true,
        minLines: 1,
        maxLines: 4,
        maxLength: 300,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Type your note'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_field.text.trim()),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
