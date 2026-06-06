import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  StorageService({FirebaseStorage? storage}) : _storage = storage ?? FirebaseStorage.instance;
  final FirebaseStorage _storage;

  Future<String> uploadProductImage(String productId, File file) async {
    final ref = _storage.ref('products/$productId.jpg');
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  Future<String> uploadDealImage(String dealId, File file) async {
    final ref = _storage.ref('deals/$dealId.jpg');
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }
}
