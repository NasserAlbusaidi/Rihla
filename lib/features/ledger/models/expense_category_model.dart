import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

/// Expense category model
class ExpenseCategory {
  final String id;
  final String tripId;
  final String name;
  final String icon;
  final String color;
  final bool isDefault;
  final DateTime? createdAt;

  const ExpenseCategory({
    required this.id,
    required this.tripId,
    required this.name,
    this.icon = 'other',
    this.color = '#22C55E',
    this.isDefault = false,
    this.createdAt,
  });

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) {
    return ExpenseCategory(
      id: json['id'] as String,
      tripId: json['trip_id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String? ?? 'other',
      color: json['color'] as String? ?? '#22C55E',
      isDefault: json['is_default'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'trip_id': tripId,
      'name': name,
      'icon': icon,
      'color': color,
      'is_default': isDefault,
    };
  }

  /// Get the IconData for this category
  IconData get iconData {
    switch (icon.toLowerCase()) {
      case 'gas':
        return Iconsax.gas_station;
      case 'food':
        return Iconsax.coffee;
      case 'gear':
        return Iconsax.bag_2;
      case 'lodging':
        return Iconsax.house;
      case 'transport':
        return Iconsax.car;
      case 'other':
      default:
        return Iconsax.receipt;
    }
  }

  /// Parse hex color string to Color
  Color get colorValue {
    try {
      final hex = color.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFF22C55E);
    }
  }
}
