import 'package:flutter/material.dart';
import 'package:flutter_translate/flutter_translate.dart';
import 'datdbase.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<Map<String, dynamic>> _notes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshNotes();
  }

  Future<void> _refreshNotes() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.queryAllNotes();
    setState(() {
      _notes = data;
      _isLoading = false;
    });
  }

  void _showNoteDialog({Map<String, dynamic>? note}) {
    final titleController = TextEditingController(text: note?['title'] ?? '');
    final contentController = TextEditingController(text: note?['content'] ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(note == null ? translate('add_note') : translate('edit_note')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Title')),
            TextField(controller: contentController, decoration: const InputDecoration(labelText: 'Content'), maxLines: 3),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(translate('cancel'))),
          ElevatedButton(
            onPressed: () async {
              final noteData = {
                'title': titleController.text,
                'content': contentController.text,
                'created_at': DateTime.now().toIso8601String(),
              };
              if (note == null) {
                await DatabaseHelper.instance.addNote(noteData);
              } else {
                noteData['note_id'] = note['note_id'];
                await DatabaseHelper.instance.updateNote(noteData);
              }
              Navigator.pop(context);
              _refreshNotes();
            },
            child: Text(translate('save')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(translate('notes')), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
              ? Center(child: Text(translate('no_notes')))
              : ListView.builder(
                  itemCount: _notes.length,
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (context, index) {
                    final note = _notes[index];
                    return Card(
                      child: ListTile(
                        title: Text(note['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(note['content']),
                        onTap: () => _showNoteDialog(note: note),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            await DatabaseHelper.instance.deleteNote(note['note_id']);
                            _refreshNotes();
                          },
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showNoteDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
