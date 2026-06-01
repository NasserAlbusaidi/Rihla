import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/keys/shared_keys.dart';
import 'package:safar/features/groups/keys/group_keys.dart';

void main() {
  group('SharedKeys', () {
    test('loadingButton includes the supplied label', () {
      expect(
        SharedKeys.loadingButton('Save').toString(),
        const Key('shared_loading_button_Save').toString(),
      );
    });
  });

  group('GroupKeys', () {
    test('groupCard includes the group id', () {
      expect(
        GroupKeys.groupCard('group-123').toString(),
        const Key('group_card_group-123').toString(),
      );
    });

    test('settlementTile includes the settlement id', () {
      expect(
        GroupKeys.settlementTile('settlement-456').toString(),
        const Key('group_settlement_tile_settlement-456').toString(),
      );
    });
  });
}
