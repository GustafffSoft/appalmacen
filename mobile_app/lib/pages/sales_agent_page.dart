import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/ai_service.dart';
import '../services/firebase_service.dart';

class SalesAgentPage extends StatefulWidget {
  const SalesAgentPage({super.key});

  @override
  State<SalesAgentPage> createState() => _SalesAgentPageState();
}

class _SalesAgentPageState extends State<SalesAgentPage> {
  final _messageController = TextEditingController();
  final Set<String> _selectedSkus = {};
  String? _prospectId;
  String _channel = 'whatsapp';
  String _language = 'es';
  bool _saving = false;
  bool _generatingAi = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _money(double value) => '\$${value.toStringAsFixed(2)}';

  String _productLabel(Map<String, dynamic> data, String docId) {
    final name = data['name']?.toString() ?? 'Producto';
    final salePrice = _toDouble(data['salePrice']);
    if (salePrice > 0) {
      return '$name (${_money(salePrice)})';
    }
    return name;
  }

  String _buildMessage({
    required Map<String, dynamic> prospect,
    required List<Map<String, dynamic>> products,
  }) {
    final businessName = prospect['businessName']?.toString() ?? 'su negocio';
    final businessType = prospect['businessType']?.toString() ?? 'negocio';
    final area = prospect['area']?.toString() ?? '';
    final productNames = products
        .map(
          (product) => _productLabel(product, product['sku']?.toString() ?? ''),
        )
        .join(', ');

    if (_language == 'en') {
      final areaText = area.isEmpty ? '' : ' in $area';
      final channelIntro = _channel == 'call'
          ? 'I wanted to quickly introduce our restaurant supply warehouse.'
          : 'I wanted to send you a quick note from our restaurant supply warehouse.';
      return 'Hi, this is Gustavo. I saw your $businessType$areaText, $businessName. $channelIntro\n\n'
          'We can help with supplies like $productNames, with local service and competitive pricing.\n\n'
          'Would you like me to send you a short catalog or a quote for the items you use most?';
    }

    final areaText = area.isEmpty ? '' : ' en $area';
    final channelIntro = _channel == 'call'
        ? 'Queria presentarle rapido nuestro almacen de supplies para restaurantes.'
        : 'Queria enviarle una nota rapida de nuestro almacen de supplies para restaurantes.';
    return 'Hola, mi nombre es Gustavo. Vi su $businessType$areaText, $businessName. $channelIntro\n\n'
        'Podemos ayudarle con productos como $productNames, con servicio local y buenos precios.\n\n'
        'Le puedo mandar un catalogo corto o una cotizacion de los productos que mas usa?';
  }

  List<Map<String, dynamic>> _selectedProductPayload(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> selectedProducts,
  ) {
    return selectedProducts.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      final sku = data['sku']?.toString() ?? doc.id;
      final salePrice = _toDouble(data['salePrice']);
      final cost = _toDouble(data['cost']);
      final marginPct = salePrice <= 0
          ? 0
          : ((salePrice - cost) / salePrice) * 100;
      data['sku'] = sku;
      data['marginPct'] = marginPct;
      return data;
    }).toList();
  }

  Future<void> _generateAiMessage({
    required QueryDocumentSnapshot<Map<String, dynamic>> prospectDoc,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> selectedProducts,
  }) async {
    final aiService = context.read<AiService>();
    setState(() => _generatingAi = true);
    try {
      final message = await aiService.generateSalesMessage(
        prospect: prospectDoc.data(),
        products: _selectedProductPayload(selectedProducts),
        channel: _channel,
        language: _language,
      );

      if (!mounted) return;
      setState(() => _messageController.text = message);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar con IA: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _generatingAi = false);
      }
    }
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

  Future<void> _saveMessage({
    required QueryDocumentSnapshot<Map<String, dynamic>> prospectDoc,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> selectedProducts,
  }) async {
    final firebaseService = context.read<FirebaseService>();
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Genera o escribe un mensaje primero')),
      );
      return;
    }

    final prospect = prospectDoc.data();
    setState(() => _saving = true);
    try {
      await firebaseService.saveSalesMessage(
        prospectId: prospectDoc.id,
        prospectName: prospect['businessName']?.toString() ?? 'Cliente',
        prospectType: prospect['businessType']?.toString() ?? '',
        productSkus: selectedProducts
            .map((doc) => doc.data()['sku']?.toString() ?? doc.id)
            .toList(),
        productNames: selectedProducts
            .map((doc) => doc.data()['name']?.toString() ?? 'Producto')
            .toList(),
        channel: _channel,
        language: _language,
        message: message,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mensaje guardado en historial')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando mensaje: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firebaseService = context.read<FirebaseService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Agente Vendedor')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: firebaseService.watchProspects(),
        builder: (context, prospectsSnapshot) {
          if (!prospectsSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: firebaseService.watchProducts(),
            builder: (context, productsSnapshot) {
              if (!productsSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final prospects = prospectsSnapshot.data!.docs;
              final products = productsSnapshot.data!.docs;
              if (prospects.isEmpty || products.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Necesitas al menos un cliente B2B y un producto para generar mensajes.',
                    ),
                  ),
                );
              }

              final prospectIds = prospects.map((doc) => doc.id).toSet();
              if (_prospectId == null || !prospectIds.contains(_prospectId)) {
                _prospectId = prospects.first.id;
              }

              final selectedProducts = products.where((doc) {
                final sku = doc.data()['sku']?.toString() ?? doc.id;
                return _selectedSkus.contains(sku);
              }).toList();
              final selectedProspect = prospects.firstWhere(
                (doc) => doc.id == _prospectId,
              );

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _prospectId,
                      decoration: const InputDecoration(
                        labelText: 'Cliente B2B',
                      ),
                      items: prospects
                          .map((doc) {
                            final data = doc.data();
                            final name =
                                data['businessName']?.toString() ?? 'Cliente';
                            final type = data['businessType']?.toString() ?? '';
                            return DropdownMenuItem(
                              value: doc.id,
                              child: Text(
                                type.isEmpty ? name : '$name - $type',
                              ),
                            );
                          })
                          .toList(growable: false),
                      onChanged: (value) => setState(() => _prospectId = value),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _channel,
                            decoration: const InputDecoration(
                              labelText: 'Canal',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'whatsapp',
                                child: Text('WhatsApp'),
                              ),
                              DropdownMenuItem(
                                value: 'sms',
                                child: Text('SMS'),
                              ),
                              DropdownMenuItem(
                                value: 'email',
                                child: Text('Email'),
                              ),
                              DropdownMenuItem(
                                value: 'call',
                                child: Text('Llamada'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _channel = value);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _language,
                            decoration: const InputDecoration(
                              labelText: 'Idioma',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'es',
                                child: Text('Español'),
                              ),
                              DropdownMenuItem(
                                value: 'en',
                                child: Text('English'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _language = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Productos para ofrecer',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...products.map((doc) {
                      final data = doc.data();
                      final sku = data['sku']?.toString() ?? doc.id;
                      final name = data['name']?.toString() ?? 'Producto';
                      final category = data['category']?.toString() ?? '';
                      final salePrice = _toDouble(data['salePrice']);
                      return CheckboxListTile(
                        value: _selectedSkus.contains(sku),
                        title: Text('$sku - $name'),
                        subtitle: Text(
                          [
                            if (category.isNotEmpty) category,
                            if (salePrice > 0) 'Venta ${_money(salePrice)}',
                          ].join(' | '),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedSkus.add(sku);
                            } else {
                              _selectedSkus.remove(sku);
                            }
                          });
                        },
                      );
                    }),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: selectedProducts.isEmpty
                            ? null
                            : () {
                                final message = _buildMessage(
                                  prospect: selectedProspect.data(),
                                  products: _selectedProductPayload(
                                    selectedProducts,
                                  ),
                                );
                                setState(
                                  () => _messageController.text = message,
                                );
                              },
                        icon: const Icon(Icons.auto_awesome_outlined),
                        label: const Text('Generar Mensaje'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: selectedProducts.isEmpty || _generatingAi
                            ? null
                            : () => _generateAiMessage(
                                prospectDoc: selectedProspect,
                                selectedProducts: selectedProducts,
                              ),
                        icon: _generatingAi
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.psychology_outlined),
                        label: Text(
                          _generatingAi
                              ? 'Generando con IA...'
                              : 'Generar con IA',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _messageController,
                      minLines: 7,
                      maxLines: 12,
                      decoration: const InputDecoration(
                        labelText: 'Mensaje generado',
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
                            onPressed: _saving
                                ? null
                                : () => _saveMessage(
                                    prospectDoc: selectedProspect,
                                    selectedProducts: selectedProducts,
                                  ),
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
              );
            },
          );
        },
      ),
    );
  }
}
