import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/erp_models.dart';
import '../services/erp_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = ErpService();
  final _brl = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  List<StoreModel> _stores = [];
  StoreModel? _selectedStore;
  List<ProductModel> _products = [];
  List<SaleModel> _sales = [];
  final List<CartItem> _cart = [];

  int _tabIndex = 0;
  String _paymentMethod = 'Pix';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      await _service.ensureProfile();
      await _loadStores();
    } catch (e) {
      _toast('Erro ao carregar dados: \$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadStores() async {
    final list = await _service.fetchMyStores();
    setState(() {
      _stores = list;
      if (_stores.isEmpty) {
        _selectedStore = null;
      } else if (_selectedStore == null || !_stores.any((s) => s.id == _selectedStore!.id)) {
        _selectedStore = _stores.first;
      } else {
        _selectedStore = _stores.firstWhere((s) => s.id == _selectedStore!.id);
      }
    });
    if (_selectedStore != null) {
      await _loadStoreData();
    } else {
      setState(() {
        _products = [];
        _sales = [];
        _cart.clear();
      });
    }
  }

  Future<void> _loadStoreData() async {
    final store = _selectedStore;
    if (store == null) return;
    final prods = await _service.fetchProducts(store.id);
    final sales = await _service.fetchSales(store.id);
    if (!mounted) return;
    setState(() {
      _products = prods;
      _sales = sales;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _dialogCreateStore() async {
    final ctrl = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cadastrar Nova Loja'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Nome da loja'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (created == true && ctrl.text.trim().isNotEmpty) {
      try {
        await _service.createStore(ctrl.text);
        await _loadStores();
        _toast('Loja cadastrada com sucesso!');
      } catch (e) {
        _toast('Erro ao criar loja: \$e');
      }
    }
  }

  Future<void> _dialogDeleteStore() async {
    final store = _selectedStore;
    if (store == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Loja'),
        content: Text(
          'Tem certeza que deseja excluir "\${store.name}"?\n\n'
          'Todos os produtos, vendas e operadores vinculados a esta loja serão apagados permanentemente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await Supabase.instance.client
          .from('stores')
          .delete()
          .eq('id', store.id);

      setState(() {
        _cart.clear();
        _tabIndex = 0;
      });
      await _loadStores();
      _toast('Loja "\${store.name}" excluída com sucesso!');
    } catch (e) {
      _toast('Erro ao excluir loja: \$e');
    }
  }

  Future<void> _dialogNewProduct() async {
    final store = _selectedStore;
    if (store == null) return;
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final stockCtrl = TextEditingController(text: '10');
    final minStockCtrl = TextEditingController(text: '5');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nova Mercadoria'),
        content
