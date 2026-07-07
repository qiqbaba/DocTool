import 'package:flutter_test/flutter_test.dart';
import 'package:doctool/utils/rename_logic.dart';

void main() {
  group('RenameLogic Tests', () {
    test('Insert Rule - Start', () {
      final rule = RenameRule(
        insertRule: InsertRule(
          enabled: true,
          text: '[NEW]_',
          position: InsertPosition.start,
        ),
      );
      final result = RenameLogic.applyRules('my_file', rule);
      expect(result, '[NEW]_my_file');
    });

    test('Insert Rule - End', () {
      final rule = RenameRule(
        insertRule: InsertRule(
          enabled: true,
          text: '_v1',
          position: InsertPosition.end,
        ),
      );
      final result = RenameLogic.applyRules('my_file', rule);
      expect(result, 'my_file_v1');
    });

    test('Insert Rule - Custom Index', () {
      final rule = RenameRule(
        insertRule: InsertRule(
          enabled: true,
          text: '_XYZ_',
          position: InsertPosition.custom,
          customIndex: 3,
        ),
      );
      final result = RenameLogic.applyRules('abcdef', rule);
      expect(result, 'abc_XYZ_def');
    });

    test('Delete Rule - Match Text', () {
      final rule = RenameRule(
        deleteRule: DeleteRule(
          enabled: true,
          mode: DeleteMode.match,
          matchText: '[TEMP]',
        ),
      );
      final result = RenameLogic.applyRules('hello_[TEMP]_world_[TEMP]', rule);
      expect(result, 'hello__world_');
    });

    test('Delete Rule - Range Ends (From Start)', () {
      final rule = RenameRule(
        deleteRule: DeleteRule(
          enabled: true,
          mode: DeleteMode.rangeEnds,
          fromStart: true,
          count: 3,
        ),
      );
      final result = RenameLogic.applyRules('abcdef', rule);
      expect(result, 'def');
    });

    test('Delete Rule - Range Ends (From End)', () {
      final rule = RenameRule(
        deleteRule: DeleteRule(
          enabled: true,
          mode: DeleteMode.rangeEnds,
          fromStart: false,
          count: 2,
        ),
      );
      final result = RenameLogic.applyRules('abcdef', rule);
      expect(result, 'abcd');
    });

    test('Delete Rule - Range Custom', () {
      final rule = RenameRule(
        deleteRule: DeleteRule(
          enabled: true,
          mode: DeleteMode.rangeCustom,
          startIndex: 1,
          endIndex: 3, // Deletes indices 1, 2, 3 (bcd)
        ),
      );
      final result = RenameLogic.applyRules('abcdef', rule);
      expect(result, 'aef');
    });

    test('Delete Rule - Anchor (Before, Include Anchor)', () {
      final rule = RenameRule(
        deleteRule: DeleteRule(
          enabled: true,
          mode: DeleteMode.anchor,
          anchorChar: '-',
          direction: DeleteDirection.before,
          includeAnchor: true,
        ),
      );
      final result = RenameLogic.applyRules('prefix-suffix', rule);
      expect(result, 'suffix');
    });

    test('Delete Rule - Anchor (Before, Exclude Anchor)', () {
      final rule = RenameRule(
        deleteRule: DeleteRule(
          enabled: true,
          mode: DeleteMode.anchor,
          anchorChar: '-',
          direction: DeleteDirection.before,
          includeAnchor: false,
        ),
      );
      final result = RenameLogic.applyRules('prefix-suffix', rule);
      expect(result, '-suffix');
    });

    test('Delete Rule - Anchor (After, Include Anchor)', () {
      final rule = RenameRule(
        deleteRule: DeleteRule(
          enabled: true,
          mode: DeleteMode.anchor,
          anchorChar: '-',
          direction: DeleteDirection.after,
          includeAnchor: true,
        ),
      );
      final result = RenameLogic.applyRules('prefix-suffix', rule);
      expect(result, 'prefix');
    });

    test('Delete Rule - Anchor (After, Exclude Anchor)', () {
      final rule = RenameRule(
        deleteRule: DeleteRule(
          enabled: true,
          mode: DeleteMode.anchor,
          anchorChar: '-',
          direction: DeleteDirection.after,
          includeAnchor: false,
        ),
      );
      final result = RenameLogic.applyRules('prefix-suffix', rule);
      expect(result, 'prefix-');
    });

    test('Parent Directory Name Insert', () {
      final rule = RenameRule(
        parentDirRule: ParentDirRule(
          enabled: true,
          position: InsertPosition.start,
        ),
      );
      final result = RenameLogic.applyRules('file', rule, parentDirName: 'FolderA');
      expect(result, 'FolderAfile');
    });

    test('Insert Rule with Separator - Start', () {
      final rule = RenameRule(
        insertRule: InsertRule(
          enabled: true,
          text: 'new',
          separator: '-',
          position: InsertPosition.start,
        ),
      );
      final result = RenameLogic.applyRules('file', rule);
      expect(result, 'new-file');
    });

    test('Insert Rule with Separator - End', () {
      final rule = RenameRule(
        insertRule: InsertRule(
          enabled: true,
          text: 'v1',
          separator: '_',
          position: InsertPosition.end,
        ),
      );
      final result = RenameLogic.applyRules('file', rule);
      expect(result, 'file_v1');
    });

    test('Insert Rule with Separator - Custom Index (Middle)', () {
      final rule = RenameRule(
        insertRule: InsertRule(
          enabled: true,
          text: 'mid',
          separator: '-',
          position: InsertPosition.custom,
          customIndex: 3,
        ),
      );
      final result = RenameLogic.applyRules('abcdef', rule);
      expect(result, 'abc-mid-def');
    });

    test('Insert Rule with Separator - Custom Index (Start)', () {
      final rule = RenameRule(
        insertRule: InsertRule(
          enabled: true,
          text: 'start',
          separator: '-',
          position: InsertPosition.custom,
          customIndex: 0,
        ),
      );
      final result = RenameLogic.applyRules('abcdef', rule);
      expect(result, 'start-abcdef');
    });

    test('Insert Rule with Separator - Custom Index (End)', () {
      final rule = RenameRule(
        insertRule: InsertRule(
          enabled: true,
          text: 'end',
          separator: '-',
          position: InsertPosition.custom,
          customIndex: 6,
        ),
      );
      final result = RenameLogic.applyRules('abcdef', rule);
      expect(result, 'abcdef-end');
    });

    test('Parent Directory Name Insert with Separator', () {
      final rule = RenameRule(
        parentDirRule: ParentDirRule(
          enabled: true,
          separator: '_v_',
          position: InsertPosition.start,
        ),
      );
      final result = RenameLogic.applyRules('file', rule, parentDirName: 'FolderA');
      expect(result, 'FolderA_v_file');
    });
  });
}
