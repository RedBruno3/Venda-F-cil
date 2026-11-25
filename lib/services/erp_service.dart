import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/erp_models.dart';

class ErpService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<void> ensureProfile() async {
    final user = _client.auth.currentUser;
    if (user == null || user.email == null) return;
    await _client.from('profiles').upsert({
      'id': user.id,
      'email': user.email!.toLowerCase(),
    });
  }

  Future<List<StoreModel>> fetchMyStores() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    final rows = await _client
        .from('store_members')
        .select('role, stores(id, name)')
        .eq('user_id', user.id);

    final list = <StoreModel>[];
    for (final row in rows as List<dynamic>) {
      final store = row['stores'] as Map<String, dynamic>?;
      if (store != null) {
        list.add(StoreModel(
          id: store['id'] as String,
          name: store['name'] as String,
          role: row['role'] as String,
        ));
      }
    }
    return list;
  }

  Future<void> createStore(String name) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Sessão expirada.');
    await _client.from('stores').insert({
      'name': name.trim(),
      'owner_id': user.id,
    });
  }

  Future<List<ProductModel>> fetchProducts(String storeId) async {
    final rows = await _client
        .from('products')
        .select()
        .eq('store_id', storeId)
        .order('name');
    return (rows as List<dynamic>)
        .map((e) => ProductModel.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createProduct({
    required String storeId,
    required String code,
    required String name,
    required double price,
    required int stock,
    required int minStock,
  }) async {
    await _client.from('products').insert({
      'store_id': storeId,
      'code': code.trim(),
      'name': name.trim(),
      'price': price,
      'stock': stock,
      'min_stock': minStock,
    });
  }

  Future<void> confirmSale({
    required String storeId,
    required String paymentMethod,
    required List<CartItem> items,
  }) async {
    final payload = items
        .map((i) => {
              'product_id': i.product.id,
              'quantity': i.quantity,
            })
        .toList();

    await _client.rpc('confirm_sale', params: {
      'p_store_id': storeId,
      'p_payment_method': paymentMethod,
      'p_items': payload,
    });
  }

  Future<List<SaleModel>> fetchSales(String storeId) async {
    final rows = await _client
        .from('sales')
        .select('id, payment_method, total, status, created_at, sale_items(product_code, product_name, quantity, unit_price)')
        .eq('store_id', storeId)
        .order('created_at', ascending: false);

    return (rows as List<dynamic>)
        .map((e) => SaleModel.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> cancelSale(String saleId) async {
    await _client.rpc('cancel_sale', params: {'p_sale_id': saleId});
  }

  Future<void> addOperator(String storeId, String email) async {
    await _client.rpc('add_store_operator', params: {
      'p_store_id': storeId,
      'p_email': email.trim(),
    });
  }
}
