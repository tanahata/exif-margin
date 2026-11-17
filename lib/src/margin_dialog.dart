import 'package:flutter/material.dart';

import 'percent_control.dart';
import 'frame.dart';

class MarginDialog extends StatefulWidget {
  const MarginDialog({super.key, required this.margins});
  final FrameMargins margins;
  @override
  State<MarginDialog> createState() => _MarginDialogState();
}

class _MarginDialogState extends State<MarginDialog> {
  final _form = GlobalKey<FormState>();
  late final _side = TextEditingController(
    text: '${(widget.margins.side * 100).round()}',
  );
  late final _top = TextEditingController(
    text: '${(widget.margins.top * 100).round()}',
  );
  late final _bottom = TextEditingController(
    text: '${(widget.margins.bottom * 100).round()}',
  );
  @override
  void dispose() {
    _side.dispose();
    _top.dispose();
    _bottom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('余白を調整'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('写真の短辺に対する割合です。'),
              const SizedBox(height: 20),
              PercentControl(
                id: 'margin_side',
                label: '左右それぞれ',
                controller: _side,
                min: 0,
                max: 20,
              ),
              PercentControl(
                id: 'margin_top',
                label: '上',
                controller: _top,
                min: 0,
                max: 20,
              ),
              PercentControl(
                id: 'margin_bottom',
                label: '下',
                controller: _bottom,
                min: 10,
                max: 50,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            const defaults = FrameMargins();
            _side.text = '${(defaults.side * 100).round()}';
            _top.text = '${(defaults.top * 100).round()}';
            _bottom.text = '${(defaults.bottom * 100).round()}';
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
                FrameMargins(
                  side: int.parse(_side.text) / 100,
                  top: int.parse(_top.text) / 100,
                  bottom: int.parse(_bottom.text) / 100,
                ),
              );
            }
          },
          child: const Text('適用'),
        ),
      ],
    );
  }
}
