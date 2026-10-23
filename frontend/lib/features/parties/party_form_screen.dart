import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';

/// Add / edit a customer or supplier. Pops with the saved [Party].
class PartyFormScreen extends StatefulWidget {
  const PartyFormScreen({super.key, required this.type, this.party});
  final PartyType type;
  final Party? party;

  @override
  State<PartyFormScreen> createState() => _PartyFormScreenState();
}

class _PartyFormScreenState extends State<PartyFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.party?.name);
  late final _phone = TextEditingController(text: widget.party?.phone);

  bool get _isEdit => widget.party != null;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    // Only name + phone are edited here; other fields keep their stored values.
    final p = widget.party;
    final input = PartyInput(
      type: widget.type,
      name: _name.text,
      phone: _phone.text.trim(),
      address: p?.address ?? '',
      company: p?.company ?? '',
      creditLimit: p?.creditLimit ?? 0,
      notes: p?.notes ?? '',
    );
    final repo = context.read<PartyRepository>();
    final saved = await runTask(
      context,
      () => _isEdit ? repo.update(widget.party!.id, input) : repo.create(input),
      success: _isEdit ? 'تم حفظ التعديلات' : 'تمت إضافة ${widget.type.label}',
    );
    if (saved != null && mounted) Navigator.pop(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'تعديل ${widget.type.label}' : '${widget.type.label} جديد')),
      body: Form(
        key: _form,
        child: MaxWidth(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _name,
                autofocus: !_isEdit,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'الاسم *', prefixIcon: Icon(Icons.person_outline)),
                validator: requiredText,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                onFieldSubmitted: (_) => _save(),
                decoration: const InputDecoration(labelText: 'رقم الهاتف', prefixIcon: Icon(Icons.phone_outlined)),
                validator: (v) => v != null && v.isNotEmpty && v.replaceAll(' ', '').length < 8 ? 'رقم غير صحيح' : null,
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomBar(child: FilledButton(onPressed: _save, child: Text(_isEdit ? 'حفظ التعديلات' : 'إضافة'))),
    );
  }
}
