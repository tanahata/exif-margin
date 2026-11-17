import 'package:flutter/material.dart';

class ManualFocalDialog extends StatefulWidget {
  const ManualFocalDialog({super.key, this.initialValue});
  final double? initialValue;

  @override
  State<ManualFocalDialog> createState() => _ManualFocalDialogState();
}

class _ManualFocalDialogState extends State<ManualFocalDialog> {
  final _form = GlobalKey<FormState>();
  late final _controller = TextEditingController(
    text:
        widget.initialValue?.toString().replaceFirst(RegExp(r'\.0$'), '') ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, double.parse(_controller.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('35mm換算値を入力'),
    content: SizedBox(
      width: 300,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('この写真の表示だけに適用します。'),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('manual_equivalent'),
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '35mm換算焦点距離',
                suffixText: 'mm',
              ),
              validator: (text) {
                final value = double.tryParse(text?.trim() ?? '');
                return value == null || !value.isFinite || value <= 0
                    ? '0より大きい数値を入力してください。'
                    : null;
              },
              onFieldSubmitted: (_) => _apply(),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
      FilledButton(onPressed: _apply, child: const Text('適用')),
    ],
  );
}
