import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

class StorageService {
  StorageService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  Future<String> uploadProductImage(String productId, File file) => _upload('products/$productId.jpg', file);
  Future<String> uploadDealImage(String dealId, File file) => _upload('deals/$dealId.jpg', file);

  Future<String> _upload(String path, File file) async {
    await _client.storage.from('product-images').uploadBinary(
          path,
          await file.readAsBytes(),
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
    return _client.storage.from('product-images').getPublicUrl(path);
  }
}
