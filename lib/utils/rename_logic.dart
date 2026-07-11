enum InsertPosition { start, end, custom }

enum RenameTarget { file, folder, both }

class InsertRule {
  final bool enabled;
  final String text;
  final InsertPosition position;
  final int customIndex;
  final String separator;

  InsertRule({
    this.enabled = false,
    this.text = '',
    this.position = InsertPosition.start,
    this.customIndex = 0,
    this.separator = '',
  });

  InsertRule copyWith({
    bool? enabled,
    String? text,
    InsertPosition? position,
    int? customIndex,
    String? separator,
  }) {
    return InsertRule(
      enabled: enabled ?? this.enabled,
      text: text ?? this.text,
      position: position ?? this.position,
      customIndex: customIndex ?? this.customIndex,
      separator: separator ?? this.separator,
    );
  }
}

enum DeleteMode { match, rangeEnds, rangeCustom, anchor }

enum DeleteDirection { before, after }

class DeleteRule {
  final bool enabled;
  final DeleteMode mode;

  // match mode
  final String matchText;

  // rangeEnds mode
  final bool fromStart;
  final int count;

  // rangeCustom mode
  final int startIndex;
  final int endIndex;

  // anchor mode
  final String anchorChar;
  final DeleteDirection direction;
  final bool includeAnchor;

  DeleteRule({
    this.enabled = false,
    this.mode = DeleteMode.match,
    this.matchText = '',
    this.fromStart = true,
    this.count = 0,
    this.startIndex = 0,
    this.endIndex = 0,
    this.anchorChar = '',
    this.direction = DeleteDirection.before,
    this.includeAnchor = false,
  });

  DeleteRule copyWith({
    bool? enabled,
    DeleteMode? mode,
    String? matchText,
    bool? fromStart,
    int? count,
    int? startIndex,
    int? endIndex,
    String? anchorChar,
    DeleteDirection? direction,
    bool? includeAnchor,
  }) {
    return DeleteRule(
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      matchText: matchText ?? this.matchText,
      fromStart: fromStart ?? this.fromStart,
      count: count ?? this.count,
      startIndex: startIndex ?? this.startIndex,
      endIndex: endIndex ?? this.endIndex,
      anchorChar: anchorChar ?? this.anchorChar,
      direction: direction ?? this.direction,
      includeAnchor: includeAnchor ?? this.includeAnchor,
    );
  }
}

class ParentDirRule {
  final bool enabled;
  final InsertPosition position;
  final int customIndex;
  final String separator;

  ParentDirRule({
    this.enabled = false,
    this.position = InsertPosition.start,
    this.customIndex = 0,
    this.separator = '',
  });

  ParentDirRule copyWith({
    bool? enabled,
    InsertPosition? position,
    int? customIndex,
    String? separator,
  }) {
    return ParentDirRule(
      enabled: enabled ?? this.enabled,
      position: position ?? this.position,
      customIndex: customIndex ?? this.customIndex,
      separator: separator ?? this.separator,
    );
  }
}

class RenameRule {
  final InsertRule insertRule;
  final DeleteRule deleteRule;
  final ParentDirRule parentDirRule;

  RenameRule({
    InsertRule? insertRule,
    DeleteRule? deleteRule,
    ParentDirRule? parentDirRule,
  })  : insertRule = insertRule ?? InsertRule(),
        deleteRule = deleteRule ?? DeleteRule(),
        parentDirRule = parentDirRule ?? ParentDirRule();

  RenameRule copyWith({
    InsertRule? insertRule,
    DeleteRule? deleteRule,
    ParentDirRule? parentDirRule,
  }) {
    return RenameRule(
      insertRule: insertRule ?? this.insertRule,
      deleteRule: deleteRule ?? this.deleteRule,
      parentDirRule: parentDirRule ?? this.parentDirRule,
    );
  }
}

class RenameLogic {
  static String applyRules(String originalBaseName, RenameRule rule,
      {String? parentDirName}) {
    String name = originalBaseName;

    // 1. Apply delete rules
    if (rule.deleteRule.enabled) {
      final del = rule.deleteRule;
      switch (del.mode) {
        case DeleteMode.match:
          if (del.matchText.isNotEmpty) {
            name = name.replaceAll(del.matchText, '');
          }
          break;
        case DeleteMode.rangeEnds:
          if (del.count > 0) {
            if (del.fromStart) {
              name = del.count >= name.length ? '' : name.substring(del.count);
            } else {
              name = del.count >= name.length
                  ? ''
                  : name.substring(0, name.length - del.count);
            }
          }
          break;
        case DeleteMode.rangeCustom:
          if (name.isNotEmpty && del.startIndex >= 0 && del.endIndex >= 0) {
            int start = del.startIndex.clamp(0, name.length);
            int end = del.endIndex.clamp(0, name.length);
            if (start <= end) {
              String left = name.substring(0, start);
              String right =
                  (end + 1 >= name.length) ? '' : name.substring(end + 1);
              name = left + right;
            }
          }
          break;
        case DeleteMode.anchor:
          if (del.anchorChar.isNotEmpty) {
            int idx = name.indexOf(del.anchorChar);
            if (idx != -1) {
              if (del.direction == DeleteDirection.before) {
                if (del.includeAnchor) {
                  name =
                      (idx + 1 >= name.length) ? '' : name.substring(idx + 1);
                } else {
                  name = name.substring(idx);
                }
              } else {
                if (del.includeAnchor) {
                  name = name.substring(0, idx);
                } else {
                  name = name.substring(0, idx + 1);
                }
              }
            }
          }
          break;
      }
    }

    // 2. Apply custom text insert rules
    if (rule.insertRule.enabled && rule.insertRule.text.isNotEmpty) {
      final ins = rule.insertRule;
      final sep = ins.separator;
      switch (ins.position) {
        case InsertPosition.start:
          name = ins.text + sep + name;
          break;
        case InsertPosition.end:
          name = name + sep + ins.text;
          break;
        case InsertPosition.custom:
          int idx = ins.customIndex.clamp(0, name.length);
          String left = name.substring(0, idx);
          String right = name.substring(idx);
          name = left +
              (idx > 0 ? sep : '') +
              ins.text +
              (idx < name.length ? sep : '') +
              right;
          break;
      }
    }

    // 3. Apply parent directory name insert rules
    if (rule.parentDirRule.enabled &&
        parentDirName != null &&
        parentDirName.isNotEmpty) {
      final pdir = rule.parentDirRule;
      final sep = pdir.separator;
      switch (pdir.position) {
        case InsertPosition.start:
          name = parentDirName + sep + name;
          break;
        case InsertPosition.end:
          name = name + sep + parentDirName;
          break;
        case InsertPosition.custom:
          int idx = pdir.customIndex.clamp(0, name.length);
          String left = name.substring(0, idx);
          String right = name.substring(idx);
          name = left +
              (idx > 0 ? sep : '') +
              parentDirName +
              (idx < name.length ? sep : '') +
              right;
          break;
      }
    }

    return name;
  }
}
