import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
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

  void _showForm(int? id) async {
    Map<String, dynamic>? existingNote;
    if (id != null) {
      existingNote = _notes.firstWhere((note) => note['note_id'] == id);
    }

    final titleController = TextEditingController(text: existingNote?['title']);
    final contentController = TextEditingController(text: existingNote?['content']);

    showModalBottomSheet(
      context: context,
      elevation: 5,
      isScrollControlled: true,
      builder: (_) => Container(
        padding: EdgeInsets.only(
          top: 15,
          left: 15,
          right: 15,
          bottom: MediaQuery.of(context).viewInsets.bottom + 120,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            TextField(
              controller: titleController,
              decoration: InputDecoration(hintText: 'title'.tr()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: contentController,
              decoration: InputDecoration(hintText: 'content'.tr()),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final title = titleController.text;
                final content = contentController.text;
                if (id == null) {
                  await _addNote({'title': title, 'content': content, 'created_at': DateTime.now().toString()});
                } else {
                  await _updateNote({'note_id': id, 'title': title, 'content': content});
                }
                titleController.text = '';
                contentController.text = '';
                Navigator.of(context).pop();
              },
              child: Text(id == null ? 'add_note'.tr() : 'update'.tr()),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _addNote(Map<String, dynamic> note) async {
    await DatabaseHelper.instance.addNote(note);
    _refreshNotes();
  }

  Future<void> _updateNote(Map<String, dynamic> note) async {
    await DatabaseHelper.instance.updateNote(note);
    _refreshNotes();
  }

  void _deleteNote(int id) async {
    await DatabaseHelper.instance.deleteNote(id);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('successfully_deleted_note'.tr()),
    ));
    _refreshNotes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('notes'.tr()),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _notes.length,
              itemBuilder: (context, index) => Card(
                color: Colors.orange[200],
                margin: const EdgeInsets.all(15),
                child: ListTile(
                  title: Text(_notes[index]['title'] ?? ''),
                  subtitle: Text(_notes[index]['content'] ?? ''),
                  trailing: SizedBox(
                    width: 100,
                    child: Row(
                      children: [
                        IconButton(icon: const Icon(Icons.edit), onPressed: () => _showForm(_notes[index]['note_id'])),
                        IconButton(icon: const Icon(Icons.delete), onPressed: () => _deleteNote(_notes[index]['note_id'])),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => _showForm(null),
      ),
    );
  }
}
