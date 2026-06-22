import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/firebase_service.dart';

class SalesFollowUpPage extends StatelessWidget {
  const SalesFollowUpPage({super.key});

  String _statusLabel(String status) {
    switch (status) {
      case 'sent':
        return 'Enviado';
      case 'replied':
        return 'Respondio';
      case 'interested':
        return 'Interesado';
      case 'follow_up':
        return 'Llamar luego';
      case 'closed':
        return 'Cerrado';
      default:
        return 'Borrador';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'sent':
        return const Color(0xFFE8F0FE);
      case 'replied':
        return const Color(0xFFFFF3CD);
      case 'interested':
        return const Color(0xFFEAF7EA);
      case 'follow_up':
        return const Color(0xFFFCE8E6);
      case 'closed':
        return const Color(0xFFF1F1F1);
      default:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    final firebaseService = context.read<FirebaseService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Seguimiento')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: firebaseService.watchSalesMessages(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Error cargando seguimiento: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No hay mensajes guardados todavia. Usa Agente Vendedor para crear el primero.',
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final prospectName =
                  data['prospectName']?.toString() ?? 'Cliente';
              final prospectType = data['prospectType']?.toString() ?? '';
              final channel = data['channel']?.toString() ?? '';
              final status = data['status']?.toString() ?? 'draft';
              final followUpDate = data['followUpDate']?.toString() ?? '';
              final productNames =
                  (data['productNames'] as List<dynamic>? ?? [])
                      .map((item) => item.toString())
                      .where((item) => item.isNotEmpty)
                      .join(', ');

              return ListTile(
                leading: const Icon(Icons.mark_chat_read_outlined),
                title: Text(
                  prospectType.isEmpty
                      ? prospectName
                      : '$prospectName - $prospectType',
                ),
                subtitle: Text(
                  [
                    if (channel.isNotEmpty) channel,
                    if (productNames.isNotEmpty) productNames,
                    if (followUpDate.isNotEmpty) 'Follow-up: $followUpDate',
                  ].join(' | '),
                ),
                trailing: Chip(
                  label: Text(_statusLabel(status)),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: _statusColor(status),
                  side: const BorderSide(color: Colors.black12),
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SalesFollowUpDetailPage(
                        messageId: doc.id,
                        initialData: data,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class SalesFollowUpDetailPage extends StatefulWidget {
  const SalesFollowUpDetailPage({
    super.key,
    required this.messageId,
    required this.initialData,
  });

  final String messageId;
  final Map<String, dynamic> initialData;

  @override
  State<SalesFollowUpDetailPage> createState() =>
      _SalesFollowUpDetailPageState();
}

class _SalesFollowUpDetailPageState extends State<SalesFollowUpDetailPage> {
  late final TextEditingController _followUpDateController;
  late final TextEditingController _notesController;
  late final TextEditingController _messageController;
  late String _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _status = widget.initialData['status']?.toString() ?? 'draft';
    _followUpDateController = TextEditingController(
      text: widget.initialData['followUpDate']?.toString() ?? '',
    );
    _notesController = TextEditingController(
      text: widget.initialData['followUpNotes']?.toString() ?? '',
    );
    _messageController = TextEditingController(
      text: widget.initialData['message']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _followUpDateController.dispose();
    _notesController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _pickFollowUpDate() async {
    final initial =
        DateTime.tryParse(_followUpDateController.text.trim()) ??
        DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() {
      _followUpDateController.text = picked.toIso8601String().split('T').first;
    });
  }

  Future<void> _copyMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: message));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Mensaje copiado')));
  }

  Future<void> _save() async {
    final firebaseService = context.read<FirebaseService>();
    setState(() => _saving = true);
    try {
      await firebaseService.updateSalesMessage(
        messageId: widget.messageId,
        status: _status,
        followUpDate: _followUpDateController.text.trim(),
        followUpNotes: _notesController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Seguimiento actualizado')));
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error actualizando seguimiento: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final prospectName =
        widget.initialData['prospectName']?.toString() ?? 'Cliente';
    final productNames =
        (widget.initialData['productNames'] as List<dynamic>? ?? [])
            .map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .join(', ');

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle Seguimiento')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              prospectName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (productNames.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(productNames),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Estado'),
              items: const [
                DropdownMenuItem(value: 'draft', child: Text('Borrador')),
                DropdownMenuItem(value: 'sent', child: Text('Enviado')),
                DropdownMenuItem(value: 'replied', child: Text('Respondio')),
                DropdownMenuItem(
                  value: 'interested',
                  child: Text('Interesado'),
                ),
                DropdownMenuItem(
                  value: 'follow_up',
                  child: Text('Llamar luego'),
                ),
                DropdownMenuItem(value: 'closed', child: Text('Cerrado')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _status = value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _followUpDateController,
              readOnly: true,
              onTap: _pickFollowUpDate,
              decoration: const InputDecoration(
                labelText: 'Proximo seguimiento',
                suffixIcon: Icon(Icons.calendar_month_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Notas de seguimiento',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _messageController,
              readOnly: true,
              minLines: 7,
              maxLines: 12,
              decoration: const InputDecoration(
                labelText: 'Mensaje',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copyMessage,
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Copiar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Guardando...' : 'Guardar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
