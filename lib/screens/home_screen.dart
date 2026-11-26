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
      _toast('Erro ao carregar dados: $e');
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
        _toast('Erro ao criar loja: $e');
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
          'Tem certeza que deseja excluir "${store.name}"?\n\n'
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
      _toast('Loja "${store.name}" excluída com sucesso!');
    } catch (e) {
      _toast('Erro ao excluir loja: $e');
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
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'Código')),
              const SizedBox(height: 10),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nome do produto')),
              const SizedBox(height: 10),
              TextField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Preço (R\$)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: stockCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Estoque inicial'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: minStockCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Estoque mínimo'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cadastrar')),
        ],
      ),
    );

    if (ok == true) {
      try {
        await _service.createProduct(
          storeId: store.id,
          code: codeCtrl.text,
          name: nameCtrl.text,
          price: double.parse(priceCtrl.text.replaceAll(',', '.')),
          stock: int.parse(stockCtrl.text),
          minStock: int.parse(minStockCtrl.text),
        );
        await _loadStoreData();
        _toast('Mercadoria cadastrada!');
      } catch (e) {
        _toast('Erro ao cadastrar produto: $e');
      }
    }
  }

  Future<void> _dialogAddOperator() async {
    final store = _selectedStore;
    if (store == null) return;
    final emailCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adicionar Operador'),
        content: TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'E-mail do operador cadastrado'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Liberar Acesso')),
        ],
      ),
    );
    if (ok == true && emailCtrl.text.trim().isNotEmpty) {
      try {
        await _service.addOperator(store.id, emailCtrl.text);
        _toast('Operador adicionado à loja!');
      } catch (e) {
        _toast('$e');
      }
    }
  }

  void _addToCart(ProductModel prod) {
    if (prod.stock <= 0) {
      _toast('Produto sem estoque disponível.');
      return;
    }
    setState(() {
      final idx = _cart.indexWhere((c) => c.product.id == prod.id);
      if (idx >= 0) {
        if (_cart[idx].quantity < prod.stock) {
          _cart[idx].quantity++;
        } else {
          _toast('Limite de estoque atingido (${prod.stock}).');
        }
      } else {
        _cart.add(CartItem(product: prod));
      }
    });
  }

  Future<void> _confirmSale() async {
    final store = _selectedStore;
    if (store == null || _cart.isEmpty) return;
    try {
      await _service.confirmSale(
        storeId: store.id,
        paymentMethod: _paymentMethod,
        items: _cart,
      );
      setState(() => _cart.clear());
      await _loadStoreData();
      _toast('Venda confirmada e estoque atualizado!');
    } catch (e) {
      _toast('Falha ao confirmar venda: $e');
    }
  }

  Future<void> _cancelSale(SaleModel sale) async {
    try {
      await _service.cancelSale(sale.id);
      await _loadStoreData();
      _toast('Venda cancelada e itens devolvidos ao estoque.');
    } catch (e) {
      _toast('Erro ao cancelar venda: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('VendaFácil'),
        actions: [
          IconButton(
            tooltip: 'Atualizar Minhas lojas',
            icon: const Icon(Icons.refresh),
            onPressed: _bootstrap,
          ),
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildStoreHeader(userEmail),
                Expanded(
                  child: _selectedStore == null
                      ? _buildEmptyStores()
                      : _buildCurrentTab(),
                ),
              ],
            ),
      bottomNavigationBar: _selectedStore == null
          ? null
          : NavigationBar(
              selectedIndex: _tabIndex,
              onDestinationSelected: (i) => setState(() => _tabIndex = i),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'Nova venda'),
                NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Produtos'),
                NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Histórico'),
                NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Relatórios'),
              ],
            ),
    );
  }

  Widget _buildStoreHeader(String userEmail) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Minhas lojas: ', style: TextStyle(fontWeight: FontWeight.w600)),
              if (_stores.isNotEmpty)
                DropdownButton<String>(
                  value: _selectedStore?.id,
                  items: _stores
                      .map((s) => DropdownMenuItem(
                            value: s.id,
                            child: Text('${s.name} (${s.isAdmin ? 'Admin' : 'Operador'})'),
                          ))
                      .toList(),
                  onChanged: (id) async {
                    if (id == null) return;
                    setState(() {
                      _selectedStore = _stores.firstWhere((s) => s.id == id);
                      _cart.clear();
                    });
                    await _loadStoreData();
                  },
                ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _dialogCreateStore,
                icon: const Icon(Icons.add_business, size: 18),
                label: const Text('Nova loja'),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(userEmail, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              if (_selectedStore?.isAdmin == true) ...[
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: 'Opções da loja',
                  onSelected: (v) {
                    if (v == 'add_op') _dialogAddOperator();
                    if (v == 'delete_store') _dialogDeleteStore();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'add_op',
                      child: Row(
                        children: [
                          Icon(Icons.person_add, size: 18),
                          SizedBox(width: 8),
                          Text('Adicionar operador'),
                        ],
                      ),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete_store',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Excluir loja', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                  child: const Chip(
                    avatar: Icon(Icons.settings, size: 16),
                    label: Text('Opções da loja'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyStores() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storefront, size: 64, color: Colors.black38),
            const SizedBox(height: 12),
            const Text('Nenhuma loja vinculada a esta conta.', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _dialogCreateStore,
              icon: const Icon(Icons.add),
              label: const Text('Cadastrar primeira loja'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTab() {
    switch (_tabIndex) {
      case 0:
        return _buildNewSaleTab();
      case 1:
        return _buildProductsTab();
      case 2:
        return _buildHistoryTab();
      default:
        return _buildReportsTab();
    }
  }

  Widget _buildNewSaleTab() {
    final total = _cart.fold<double>(0, (sum, item) => sum + item.subtotal);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 768;
        final catalogCard = Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Produtos Disponíveis', style: Theme.of(context).textTheme.titleMedium),
                const Divider(),
                if (_products.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('Cadastre produtos na aba Produtos para iniciar vendas.'),
                  )
                else
                  ..._products.map((p) => ListTile(
                        dense: true,
                        title: Text('[${p.code}] ${p.name}'),
                        subtitle: Text('${_brl.format(p.price)} • Estoque: ${p.stock}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.add_shopping_cart),
                          onPressed: p.stock > 0 ? () => _addToCart(p) : null,
                        ),
                      )),
              ],
            ),
          ),
        );

        final cartCard = Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Carrinho', style: Theme.of(context).textTheme.titleMedium),
                const Divider(),
                if (_cart.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('Adicione produtos ao carrinho para registrar a venda.'),
                  )
                else
                  ..._cart.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final item = entry.value;
                    return ListTile(
                      dense: true,
                      title: Text(item.product.name),
                      subtitle: Text('${_brl.format(item.product.price)} x ${item.quantity} = ${_brl.format(item.subtotal)}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () {
                              setState(() {
                                if (item.quantity > 1) {
                                  item.quantity--;
                                } else {
                                  _cart.removeAt(idx);
                                }
                              });
                            },
                          ),
                          Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => _addToCart(item.product),
                          ),
                        ],
                      ),
                    );
                  }),
                const Divider(),
                DropdownButtonFormField<String>(
                  value: _paymentMethod,
                  decoration: const InputDecoration(labelText: 'Forma de pagamento (demonstração)'),
                  items: const [
                    DropdownMenuItem(value: 'Dinheiro', child: Text('Dinheiro')),
                    DropdownMenuItem(value: 'Pix', child: Text('Pix')),
                    DropdownMenuItem(value: 'Cartão de Crédito', child: Text('Cartão de Crédito')),
                    DropdownMenuItem(value: 'Cartão de Débito', child: Text('Cartão de Débito')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _paymentMethod = v);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(_brl.format(total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton(
                    onPressed: _cart.isEmpty ? null : _confirmSale,
                    child: const Text('Confirmar Venda'),
                  ),
                ),
              ],
            ),
          ),
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: catalogCard),
                    const SizedBox(width: 16),
                    Expanded(child: cartCard),
                  ],
                )
              : Column(children: [catalogCard, const SizedBox(height: 12), cartCard]),
        );
      },
    );
  }

  Widget _buildProductsTab() {
    final isAdmin = _selectedStore?.isAdmin == true;
    return Scaffold(
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: _dialogNewProduct,
              icon: const Icon(Icons.add),
              label: const Text('Novo produto'),
            )
          : null,
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _products.length,
        itemBuilder: (context, index) {
          final p = _products[index];
          return Card(
            color: p.isLowStock ? Colors.red.shade50 : null,
            child: ListTile(
              title: Text('[${p.code}] ${p.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('Preço: ${_brl.format(p.price)} • Mínimo: ${p.minStock}'),
              trailing: Chip(
                label: Text('Estoque: ${p.stock}'),
                backgroundColor: p.isLowStock ? Colors.red.shade100 : Colors.green.shade100,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHistoryTab() {
    final isAdmin = _selectedStore?.isAdmin == true;
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');

    if (_sales.isEmpty) {
      return const Center(child: Text('Nenhuma operação registrada nesta loja.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _sales.length,
      itemBuilder: (context, index) {
        final s = _sales[index];
        return Card(
          child: ExpansionTile(
            title: Text('${_brl.format(s.total)} • ${s.paymentMethod}'),
            subtitle: Text('${dateFmt.format(s.createdAtBrasilia)} (Brasília) • ${s.isCanceled ? 'CANCELADA' : 'CONCLUÍDA'}'),
            trailing: isAdmin && !s.isCanceled
                ? TextButton(
                    onPressed: () => _cancelSale(s),
                    child: const Text('Cancelar venda', style: TextStyle(color: Colors.red)),
                  )
                : null,
            children: s.items
                .map((i) => ListTile(
                      dense: true,
                      title: Text('[${i.productCode}] ${i.productName}'),
                      trailing: Text('${i.quantity}x ${_brl.format(i.unitPrice)}'),
                    ))
                .toList(),
          ),
        );
      },
    );
  }

  Widget _buildReportsTab() {
    final nowBrt = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    final activeSales = _sales.where((s) => !s.isCanceled).toList();

    final dailyTotal = activeSales
        .where((s) {
          final d = s.createdAtBrasilia;
          return d.year == nowBrt.year && d.month == nowBrt.month && d.day == nowBrt.day;
        })
        .fold<double>(0, (sum, s) => sum + s.total);

    final monthlyTotal = activeSales
        .where((s) {
          final d = s.createdAtBrasilia;
          return d.year == nowBrt.year && d.month == nowBrt.month;
        })
        .fold<double>(0, (sum, s) => sum + s.total);

    final lowStockAlerts = _products.where((p) => p.isLowStock).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.today, color: Colors.green),
              title: const Text('Faturamento Diário (Horário de Brasília)'),
              trailing: Text(_brl.format(dailyTotal), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_month, color: Colors.blue),
              title: const Text('Faturamento Mensal (Horário de Brasília)'),
              trailing: Text(_brl.format(monthlyTotal), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.warning_amber, color: Colors.orange),
              title: const Text('Produtos com Estoque Mínimo ou Abaixo'),
              trailing: Text('$lowStockAlerts', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
