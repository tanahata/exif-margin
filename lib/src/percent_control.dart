import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A single percentage, editable either with the slider or with the keyboard.
class PercentControl extends StatefulWidget {
  const PercentControl({
    super.key,
    required this.id,
    required this.label,
    required this.controller,
    required this.min,
    required this.max,
  });
  final String id, label;
  final TextEditingController controller;
  final int min, max;
  @override
  State<PercentControl> createState() => _PercentControlState();
}

class _PercentControlState extends State<PercentControl> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(PercentControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = (int.tryParse(widget.controller.text) ?? widget.min)
        .clamp(widget.min, widget.max)
        .toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(widget.label)),
              SizedBox(
                width: 105,
                child: TextFormField(
                  key: ValueKey(widget.id),
                  controller: widget.controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: InputDecoration(
                    suffixText: '%',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                  validator: (text) {
                    final n = int.tryParse(text ?? '');
                    return n == null || n < widget.min || n > widget.max
                        ? '${widget.min}〜${widget.max}で入力'
                        : null;
                  },
                ),
              ),
            ],
          ),
          SizedBox(
            height: 32,
            child: Slider(
              key: ValueKey('${widget.id}_slider'),
              value: value,
              min: widget.min.toDouble(),
              max: widget.max.toDouble(),
              divisions: widget.max - widget.min,
              label: '${value.round()}%',
              onChanged: (n) => widget.controller.text = '${n.round()}',
            ),
          ),
          Text(
            '${widget.min}〜${widget.max}%',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
