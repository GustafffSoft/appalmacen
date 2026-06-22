import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const initialAdminEmail = 'gustafff93s@gmail.com';

class AppUserProfile {
  const AppUserProfile({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    required this.active,
  });

  final String uid;
  final String email;
  final String name;
  final String role;
  final bool active;

  bool get isAdmin => role == 'admin' && active;
  bool get isWarehouse => role == 'warehouse' && active;
  bool get isSales => role == 'sales' && active;

  factory AppUserProfile.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    return AppUserProfile(
      uid: snapshot.id,
      email: data['email']?.toString() ?? '',
      name: data['name']?.toString() ?? '',
      role: data['role']?.toString() ?? 'pending',
      active: data['active'] == true,
    );
  }
}

class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Stream<AppUserProfile?> watchProfile(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return AppUserProfile.fromSnapshot(snapshot);
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchUsers() {
    return _firestore.collection('users').snapshots();
  }

  Future<void> signIn({required String email, required String password}) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await ensureProfile(credential.user!);
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await credential.user!.updateDisplayName(name.trim());
    await ensureProfile(credential.user!, requestedName: name);
  }

  Future<void> ensureProfile(User user, {String? requestedName}) async {
    final reference = _firestore.collection('users').doc(user.uid);
    final existing = await reference.get();
    if (existing.exists) return;

    final email = (user.email ?? '').trim().toLowerCase();
    final isInitialAdmin = email == initialAdminEmail;
    await reference.set({
      'uid': user.uid,
      'email': email,
      'name': (requestedName ?? user.displayName ?? email).trim(),
      'role': isInitialAdmin ? 'admin' : 'pending',
      'active': isInitialAdmin,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateUserRole({
    required String uid,
    required String role,
  }) async {
    final validRoles = {'pending', 'warehouse', 'sales', 'admin'};
    if (!validRoles.contains(role)) {
      throw Exception('Rol no valido.');
    }
    await _firestore.collection('users').doc(uid).set({
      'role': role,
      'active': role != 'pending',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> sendPasswordReset(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() => _auth.signOut();
}
