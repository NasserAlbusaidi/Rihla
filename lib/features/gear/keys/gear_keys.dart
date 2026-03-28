import 'package:flutter/material.dart';

abstract final class GearKeys {
  // Screen key
  static const screen = Key('gear_screen');

  // Actions
  static const addButton = Key('gear_add_button');

  // Parameterized keys for list items
  static Key gearItem(String id) => Key('gear_item_$id');
}
