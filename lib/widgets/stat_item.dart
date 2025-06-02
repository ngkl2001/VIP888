import 'package:flutter/material.dart';
import '../utils/format_utils.dart';

class StatItem extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const StatItem({
    Key? key,
    required this.label,
    required this.value,
    required this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label == '筆數'
              ? value.toStringAsFixed(0)
              : formatMoney(value),
          style: TextStyle(
            fontSize: 16,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
} 