import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';

class AdminUsersPage extends StatelessWidget {
  const AdminUsersPage({super.key});

  static const _roles = <String, String>{
    'pending': 'Sin acceso',
    'warehouse': 'Almacen',
    'sales': 'Ventas',
    'admin': 'Administrador',
  };

  @override
  Widget build(BuildContext context) {
    final authService = context.read<AuthService>();
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Administracion de usuarios')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: authService.watchUsers(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snapshot.data!.docs.toList()
            ..sort((a, b) {
              final roleA = a.data()['role']?.toString() ?? 'pending';
              final roleB = b.data()['role']?.toString() ?? 'pending';
              if (roleA == 'pending' && roleB != 'pending') return -1;
              if (roleA != 'pending' && roleB == 'pending') return 1;
              final emailA = a.data()['email']?.toString() ?? '';
              final emailB = b.data()['email']?.toString() ?? '';
              return emailA.compareTo(emailB);
            });
          if (users.isEmpty) {
            return const Center(child: Text('No hay usuarios registrados.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: users.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final doc = users[index];
              final data = doc.data();
              final email = data['email']?.toString() ?? '';
              final name = data['name']?.toString() ?? '';
              final role = data['role']?.toString() ?? 'pending';
              final isCurrentUser = doc.id == currentUid;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        child: Icon(
                          role == 'pending'
                              ? Icons.hourglass_empty
                              : Icons.person_outline,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name.isEmpty ? email : name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(email),
                            if (isCurrentUser)
                              const Text(
                                'Tu cuenta',
                                style: TextStyle(fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: _roles.containsKey(role) ? role : 'pending',
                        items: _roles.entries
                            .map(
                              (entry) => DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.value),
                              ),
                            )
                            .toList(),
                        onChanged: isCurrentUser
                            ? null
                            : (value) async {
                                if (value == null) return;
                                await authService.updateUserRole(
                                  uid: doc.id,
                                  role: value,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        value == 'pending'
                                            ? 'Acceso retirado a $email'
                                            : 'Rol actualizado para $email',
                                      ),
                                    ),
                                  );
                                }
                              },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
