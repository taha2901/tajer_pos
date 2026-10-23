import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/format.dart';
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
  late final _address = TextEditingController(text: widget.party?.address);
  late final _company = TextEditingController(text: widget.party?.company);
  late final _limit = TextEditingController(text: widget.party == null || widget.party!.creditLimit == 0 ? '' : Fmt.qty(widget.party!.creditLimit));
  final _opening = TextEditingController();
  late final _notes = TextEditingController(text: widget.party?.notes);

  bool get _isEdit => widget.party != null;
  bool get _isCustomer => widget.type == PartyType.customer;

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _company, _limit, _opening, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final input = PartyInput(
      type: widget.type,
      name: _name.text,
      phone: _phone.text.trim(),
      address: _address.text.trim(),
      company: _company.text.trim(),
      creditLimit: parseNum(_limit.text) ?? 0,
      openingBalance: parseNum(_opening.text) ?? 0,
      notes: _notes.text.trim(),
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
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'رقم الهاتف', prefixIcon: Icon(Icons.phone_outlined)),
                validator: (v) => v != null && v.isNotEmpty && v.replaceAll(' ', '').length < 8 ? 'رقم غير صحيح' : null,
              ),
              const SizedBox(height: 12),
              if (!_isCustomer) ...[
                TextFormField(
                  controller: _company,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'الشركة', prefixIcon: Icon(Icons.business_outlined)),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _address,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'العنوان', prefixIcon: Icon(Icons.location_on_outlined)),
              ),
              const SizedBox(height: 18),
              MoneyField(
                controller: _limit,
                label: 'حد الائتمان',
                helper: _isCustomer ? 'أقصى مديونية مسموحة للعميل. اتركه فارغاً بدون حد' : 'أقصى مستحق للمورد (للمتابعة فقط)',
              ),
              if (!_isEdit) ...[
                const SizedBox(height: 12),
                MoneyField(
                  controller: _opening,
                  label: 'رصيد افتتاحي',
                  helper: _isCustomer ? 'مديونية سابقة على العميل قبل استخدام النظام' : 'مستحقات سابقة للمورد قبل استخدام النظام',
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'ملاحظات', alignLabelWithHint: true),
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
