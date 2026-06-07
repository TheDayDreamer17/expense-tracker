import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/db/database_helper.dart';
import '../../core/utils/app_theme.dart';

class CreateCategoryDialog extends StatefulWidget {
  final String initialType; // 'EXPENSE' or 'INCOME'
  final int transactionMonth;
  final int transactionYear;

  const CreateCategoryDialog({
    super.key,
    required this.initialType,
    required this.transactionMonth,
    required this.transactionYear,
  });

  @override
  State<CreateCategoryDialog> createState() => _CreateCategoryDialogState();
}

class _CreateCategoryDialogState extends State<CreateCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _iconController = TextEditingController(text: '🍕');
  final _limitController = TextEditingController();
  
  late String _type;
  late int _selectedColor;
  bool _saving = false;

  final List<int> _colors = [
    0xFFFF5252, // Red
    0xFFFF4081, // Pink
    0xFFE040FB, // Purple
    0xFF7C4DFF, // Deep Purple
    0xFF536DFE, // Indigo
    0xFF448AFF, // Blue
    0xFF00B0FF, // Light Blue
    0xFF1DE9B6, // Teal
    0xFF00E676, // Green
    0xFFFFD740, // Amber
    0xFFFF9100, // Orange
    0xFFFF3D00, // Deep Orange
    0xFF9E9E9E, // Grey
  ];

  final List<String> _popularEmojis = [
    '🍕', '🛒', '🚗', '🛍️', '🎬', '💊', '⚡', '📱', '🎓', '🔄',
    '✈️', '💰', '💼', '📈', '🎁', '💵', '🏠', '🎮', '🏋️', '🐾'
  ];

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _selectedColor = _colors.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _iconController.dispose();
    _limitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? AppColors.darkSurface : Colors.white;

    return Dialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Create Category',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Name Input
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Category Name',
                    prefixIcon: Icon(Icons.label_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Icon / Emoji Selector
                const Text(
                  'Select Icon / Emoji',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.lightTextSecondary),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Color(_selectedColor).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Color(_selectedColor), width: 1.5),
                      ),
                      child: Center(
                        child: Text(
                          _iconController.text.isEmpty ? '❓' : _iconController.text,
                          style: const TextStyle(fontSize: 26),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _iconController,
                        decoration: const InputDecoration(
                          hintText: 'Type any emoji',
                          labelText: 'Custom Emoji',
                        ),
                        maxLength: 2,
                        buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                        onChanged: (val) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _popularEmojis.length,
                    itemBuilder: (context, index) {
                      final emoji = _popularEmojis[index];
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _iconController.text = emoji;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: CircleAvatar(
                            backgroundColor: isDark ? AppColors.darkCard : Colors.grey.shade100,
                            radius: 18,
                            child: Text(emoji, style: const TextStyle(fontSize: 18)),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Color Selector
                const Text(
                  'Select Color',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.lightTextSecondary),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _colors.length,
                    itemBuilder: (context, index) {
                      final color = _colors[index];
                      final isSelected = color == _selectedColor;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedColor = color),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: CircleAvatar(
                            backgroundColor: Color(color),
                            radius: 16,
                            child: isSelected
                                ? const Icon(Icons.check, color: Colors.white, size: 16)
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Limit Selector
                if (_type == 'EXPENSE') ...[
                  const Text(
                    'Monthly Limit (Optional)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.lightTextSecondary),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _limitController,
                    decoration: const InputDecoration(
                      hintText: 'Enter monthly budget limit (e.g. 5000)',
                      prefixIcon: Icon(Icons.warning_amber_rounded),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                ],

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Create'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final db = DatabaseHelper.instance;
      final categoryId = 'cat_${const Uuid().v4()}';
      final name = _nameController.text.trim();
      final icon = _iconController.text.trim();

      // Insert Category
      final categoryMap = {
        'id': categoryId,
        'name': name,
        'type': _type,
        'icon': icon.isEmpty ? '❓' : icon,
        'color': _selectedColor,
        'parent_id': null,
      };
      await db.insert('categories', categoryMap);

      // Insert Budget Limit if provided
      final limitVal = double.tryParse(_limitController.text.trim());
      if (_type == 'EXPENSE' && limitVal != null && limitVal > 0) {
        final budgetId = 'bud_${const Uuid().v4()}';
        final budgetMap = {
          'id': budgetId,
          'category_id': categoryId,
          'month': widget.transactionMonth,
          'year': widget.transactionYear,
          'amount': limitVal,
        };
        await db.insert('budgets', budgetMap);
      }

      if (mounted) {
        Navigator.pop(context, categoryId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating category: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
