import 'package:flutter/material.dart';

import 'caption_sizes.dart';
import 'percent_control.dart';
import 'public_edition.dart';

class SizeDialog extends StatefulWidget {
  const SizeDialog({super.key, required this.sizes});
  final CaptionSizes sizes;
  @override
  State<SizeDialog> createState() => _SizeDialogState();
}

class _SizeDialogState extends State<SizeDialog> {
  final _form = GlobalKey<FormState>();
  late final _left = TextEditingController(
    text: '${(widget.sizes.left * 100).round()}',
  );
  late final _right = TextEditingController(
    text: '${(widget.sizes.right * 100).round()}',
  );
  @override
  void dispose() {
    _left.dispose();
    _right.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('左右のサイズ調整'),
    content: SizedBox(
      width: 380,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              kPublicTextOnly
                  ? '写真の横幅の2.4%が100%です。'
                  : '写真の横幅の2.4%が100%です。ロゴは左の文字と連動します。',
            ),
            const SizedBox(height: 20),
            PercentControl(
              id: 'left_size',
              label: kPublicTextOnly ? '機種名' : 'ロゴ・機種名',
              controller: _left,
              min: 50,
              max: 200,
            ),
            PercentControl(
              id: 'right_size',
              label: 'レンズ名・撮影情報',
              controller: _right,
              min: 50,
              max: 200,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          _left.text = '100';
          _right.text = '100';
        },
        child: const Text('初期値に戻す'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(
              context,
              CaptionSizes(
                left: int.parse(_left.text) / 100,
                right: int.parse(_right.text) / 100,
              ),
            );
          }
        },
        child: const Text('適用'),
      ),
    ],
  );
}
