import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

class StorageService {
  StorageService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  Future<String> uploadProductImage(String productId, File file) => _upload('products/$productId.jpg', file);
  Future<String> uploadDealImage(String dealId, File file) => _upload('deals/$dealId.jpg', file);
  Future<String> uploadImage(String folder, String key, File file) {
    final extension = file.path.split('.').last.toLowerCase();
    final safeExtension = const ['jpg', 'jpeg', 'png', 'webp'].contains(extension) ? extension : 'jpg';
    return _upload('$folder/$key.$safeExtension', file);
  }

  Future<String> _upload(String path, File file) async {
    final extension = path.split('.').last;
    final contentType = extension == 'png'
        ? 'image/png'
        : extension == 'webp'
            ? 'image/webp'
            : 'image/jpeg';
    await _client.storage.from('product-images').uploadBinary(
          path,
          await file.readAsBytes(),
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return _client.storage.from('product-images').getPublicUrl(path);
  }
}
