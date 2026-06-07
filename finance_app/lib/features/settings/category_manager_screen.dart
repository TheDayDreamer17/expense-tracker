import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:uuid/uuid.dart';
import '../../core/db/database_helper.dart';
import '../../core/models/models.dart';
import '../../core/utils/app_theme.dart';
import '../../widgets/shared/create_category_dialog.dart';

class CategoryManagerScreen extends ConsumerStatefulWidget {
  const CategoryManagerScreen({super.key});
  @override
  ConsumerState<CategoryManagerScreen> createState() => _CategoryManagerScreenState();
}

class _CategoryManagerScreenState extends ConsumerState<CategoryManagerScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<CategoryModel> _categories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = DatabaseHelper.instance;
    final rows = await db.query('categories');
    if (mounted) {
      setState(() {
        _categories = rows.map(CategoryModel.fromMap).toList();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Categories'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Expense'),
            Tab(text: 'Income'),
            Tab(text: 'Transfer'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCategoryList('EXPENSE'),
                _buildCategoryList('INCOME'),
                _buildCategoryList('TRANSFER'),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddCategoryDialog,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildCategoryList(String type) {
    final list = _categories.where((c) => c.type == type).toList();
    final parents = list.where((c) => c.parentId == null).toList();

    if (parents.isEmpty) {
      return const Center(child: Text('No categories found.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: parents.length,
      itemBuilder: (context, index) {
        final parent = parents[index];
        final children = list.where((c) => c.parentId == parent.id).toList();

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            leading: Text(parent.icon, style: const TextStyle(fontSize: 24)),
            title: Text(
              parent.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.expense, size: 20),
              onPressed: () => _deleteCategory(parent),
            ),
            children: [
              if (children.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Text(
                    'No subcategories yet.',
                    style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                  ),
                )
              else
                ...children.map((child) => ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                      title: Text(child.name, style: const TextStyle(fontSize: 13)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppColors.expense, size: 18),
                        onPressed: () => _deleteCategory(child),
                      ),
                    )),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: const Icon(Icons.add, size: 18, color: AppColors.primary),
                title: const Text('Add Subcategory', style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.bold)),
                onTap: () => _showAddSubcategoryDialog(parent),
              )
            ],
          ),
        ).animate().fadeIn(delay: (index * 40).ms);
      },
    );
  }

  void _showAddCategoryDialog() async {
    final types = ['EXPENSE', 'INCOME', 'TRANSFER'];
    final type = types[_tabController.index];
    final now = DateTime.now();

    final newCatId = await showDialog<String>(
      context: context,
      builder: (ctx) => CreateCategoryDialog(
        initialType: type == 'TRANSFER' ? 'EXPENSE' : type,
        transactionMonth: now.month,
        transactionYear: now.year,
      ),
    );

    if (newCatId != null) {
      _load();
    }
  }

  void _showAddSubcategoryDialog(CategoryModel parent) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Subcategory to ${parent.name}'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Subcategory Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final db = DatabaseHelper.instance;
                final id = '${parent.id}_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
                
                await db.insert('categories', {
                  'id': id,
                  'name': name,
                  'type': parent.type,
                  'icon': parent.icon,
                  'color': parent.color,
                  'parent_id': parent.id,
                });
                Navigator.pop(ctx);
                _load();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCategory(CategoryModel category) async {
    final isParent = category.parentId == null;
    final typeText = isParent ? 'category' : 'subcategory';
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $typeText?'),
        content: Text(
          isParent
              ? 'Are you sure you want to delete the category "${category.name}" and all its subcategories? All existing transactions under this category tree will be moved to "Others".'
              : 'Are you sure you want to delete the subcategory "${category.name}"? All existing transactions under this subcategory will be moved to "Others".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.expense),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final db = DatabaseHelper.instance;
      final fallbackId = category.type == 'INCOME' ? 'cat_other_inc' : 'cat_other_exp';
      
      if (isParent) {
        final children = _categories.where((c) => c.parentId == category.id).toList();
        for (final child in children) {
          await db.update('transactions', {'category_id': fallbackId}, where: 'category_id = ?', whereArgs: [child.id]);
          await db.delete('categories', where: 'id = ?', whereArgs: [child.id]);
        }
        
        await db.update('transactions', {'category_id': fallbackId}, where: 'category_id = ?', whereArgs: [category.id]);
        await db.delete('categories', where: 'id = ?', whereArgs: [category.id]);
      } else {
        await db.update('transactions', {'category_id': fallbackId}, where: 'category_id = ?', whereArgs: [category.id]);
        await db.delete('categories', where: 'id = ?', whereArgs: [category.id]);
      }
      
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted category: ${category.name}')),
      );
    }
  }
}
