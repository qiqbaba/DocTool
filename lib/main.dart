import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

import 'utils/theme_helper.dart';
import 'utils/rename_logic.dart';
import 'utils/file_helper.dart';
import 'widgets/android_dir_picker.dart';
import 'widgets/rename_rule_panel.dart';
import 'widgets/preview_panel.dart';

import 'utils/delete_logic.dart';
import 'widgets/delete_rule_panel.dart';
import 'widgets/delete_preview_panel.dart';

import 'utils/move_logic.dart';
import 'widgets/move_rule_panel.dart';
import 'widgets/move_preview_panel.dart';

import 'utils/sniffer_logic.dart';
import 'widgets/sniffer_rule_panel.dart';
import 'widgets/sniffer_preview_panel.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/theme_setting.txt');
      if (await file.exists()) {
        final content = await file.readAsString();
        final mode = ThemeMode.values.firstWhere(
          (e) => e.name == content.trim(),
          orElse: () => ThemeMode.system,
        );
        setState(() {
          _themeMode = mode;
        });
      }
    } catch (e) {
      debugPrint('Failed to load theme settings: $e');
    }
  }

  Future<void> _saveTheme(ThemeMode mode) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/theme_setting.txt');
      await file.writeAsString(mode.name);
    } catch (e) {
      debugPrint('Failed to save theme settings: $e');
    }
  }

  void _updateThemeMode(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
    _saveTheme(mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DocTool - 重复操作解决助手',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: Colors.indigoAccent,
          secondary: Colors.indigoAccent,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F3F7),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFEEEEEE),
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Colors.indigoAccent,
          secondary: Colors.indigoAccent,
          surface: Color(0xFF121214),
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0F12),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF16161A),
          elevation: 0,
        ),
      ),
      home: MainDashboard(
        currentThemeMode: _themeMode,
        onThemeModeChanged: _updateThemeMode,
      ),
    );
  }
}

class MainDashboard extends StatefulWidget {
  final ThemeMode currentThemeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const MainDashboard({
    super.key,
    required this.currentThemeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard>
    with TickerProviderStateMixin {
  String _selectedDirPath = '';
  int _currentTab = 0; // 0 for Rename, 1 for Delete

  // --- Rename States ---
  RenameRule _renameRule = RenameRule();
  RenameTarget _renameTarget = RenameTarget.file;
  bool _recursive = false;
  String _extensionFilter = '';
  bool _isScanning = false;
  List<RenameItem> _renameItems = [];
  TabController? _mobileRenameTabController;

  // --- Delete States ---
  DeleteFilterRule _deleteRule = DeleteFilterRule();
  bool _deleteRecursive = false;
  bool _isDeletingScan = false;
  double _deleteScanProgress = 0.0;
  String _deleteScanStatus = '';
  List<DeleteItem> _deleteItems = [];
  TabController? _mobileDeleteTabController;
  Timer? _deleteDebounceTimer;

  // --- Move States ---
  MoveFilterRule _moveRule = MoveFilterRule();
  bool _moveRecursive = false;
  String _targetDirPath = '';
  ConflictStrategy _conflictStrategy = ConflictStrategy.autoRename;
  bool _isMovingScan = false;
  double _moveScanProgress = 0.0;
  String _moveScanStatus = '';
  List<MoveItem> _moveItems = [];
  TabController? _mobileMoveTabController;
  Timer? _moveDebounceTimer;

  // --- Sniffer States ---
  SnifferRule _snifferRule = SnifferRule();
  bool _isSnifferScan = false;
  double _snifferScanProgress = 0.0;
  String _snifferScanStatus = '';
  List<SnifferFolderItem> _snifferItems = [];
  TabController? _mobileSnifferTabController;

  @override
  void initState() {
    super.initState();
    // Default initial rules
    _renameRule = RenameRule(
      insertRule: InsertRule(),
      deleteRule: DeleteRule(),
      parentDirRule: ParentDirRule(),
    );
    _deleteRule = DeleteFilterRule();
    _moveRule = MoveFilterRule();
    _snifferRule = SnifferRule();
  }

  @override
  void dispose() {
    _mobileRenameTabController?.dispose();
    _mobileDeleteTabController?.dispose();
    _mobileMoveTabController?.dispose();
    _mobileSnifferTabController?.dispose();
    _deleteDebounceTimer?.cancel();
    _moveDebounceTimer?.cancel();
    super.dispose();
  }

  /// Request permission and show directory picker
  Future<void> _selectDirectory() async {
    if (kIsWeb) return;

    if (Platform.isAndroid) {
      final granted = await FileHelper.requestStoragePermission();
      if (!granted) {
        _showPermissionRequiredDialog();
        return;
      }

      if (!mounted) return;
      final path = await showDialog<String>(
        context: context,
        builder: (context) => const AndroidDirPicker(),
      );

      if (path != null && path.isNotEmpty) {
        setState(() {
          _selectedDirPath = path;
          if (_currentTab == 2 && _moveRule.flattenToRoot) {
            _targetDirPath = path;
          }
        });
      }
    } else {
      // Windows
      String dialogTitle = '选择文件夹';
      if (_currentTab == 0) {
        dialogTitle = '选择要重命名的文件夹';
      } else if (_currentTab == 1) {
        dialogTitle = '选择要清理的文件夹';
      } else if (_currentTab == 2) {
        dialogTitle = '选择要移动的文件夹';
      } else if (_currentTab == 3) {
        dialogTitle = '选择要进行文件嗅探的文件夹';
      }
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: dialogTitle,
      );

      if (path != null && path.isNotEmpty) {
        setState(() {
          _selectedDirPath = path;
          if (_currentTab == 2 && _moveRule.flattenToRoot) {
            _targetDirPath = path;
          }
        });
      }
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: context.cardBg,
          title: Text(
            '主题设置',
            style: TextStyle(
                color: context.textColorPrimary, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<ThemeMode>(
                title: Text('亮色模式',
                    style: TextStyle(color: context.textColorPrimary)),
                value: ThemeMode.light,
                groupValue: widget.currentThemeMode,
                activeColor: Colors.indigoAccent,
                onChanged: (ThemeMode? value) {
                  if (value != null) {
                    widget.onThemeModeChanged(value);
                    Navigator.pop(context);
                  }
                },
              ),
              RadioListTile<ThemeMode>(
                title: Text('暗色模式',
                    style: TextStyle(color: context.textColorPrimary)),
                value: ThemeMode.dark,
                groupValue: widget.currentThemeMode,
                activeColor: Colors.indigoAccent,
                onChanged: (ThemeMode? value) {
                  if (value != null) {
                    widget.onThemeModeChanged(value);
                    Navigator.pop(context);
                  }
                },
              ),
              RadioListTile<ThemeMode>(
                title: Text('跟随系统',
                    style: TextStyle(color: context.textColorPrimary)),
                value: ThemeMode.system,
                groupValue: widget.currentThemeMode,
                activeColor: Colors.indigoAccent,
                onChanged: (ThemeMode? value) {
                  if (value != null) {
                    widget.onThemeModeChanged(value);
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('关闭',
                  style: TextStyle(color: context.textColorSecondary)),
            ),
          ],
        );
      },
    );
  }

  void _showPermissionRequiredDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.cardBg,
        title: Text('需要存储管理权限',
            style: TextStyle(
                color: context.textColorPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          '在 Android 11 及以上版本中，软件需要“所有文件访问权限”才能遍历外部文件夹并执行高速文件操作。请在接下来的设置中开启此权限。',
          style: TextStyle(color: context.textColorSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                Text('取消', style: TextStyle(color: context.textColorSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.indigoAccent),
            child: const Text('去设置授权', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Trigger directory scanning for Rename
  Future<void> _scanDirectory() async {
    if (_selectedDirPath.isEmpty) return;

    setState(() {
      _isScanning = true;
    });

    final items = await FileHelper.scanDirectory(
      rootPath: _selectedDirPath,
      isTargetFile: _renameTarget == RenameTarget.file ||
          _renameTarget == RenameTarget.both,
      isTargetFolder: _renameTarget == RenameTarget.folder ||
          _renameTarget == RenameTarget.both,
      recursive: _recursive,
      extensionFilter: _extensionFilter,
    );

    if (mounted) {
      setState(() {
        _renameItems = items;
        _isScanning = false;
        _applyRulesToPreview();
      });
    }
  }

  /// Apply Rename Rules to the scanned items to compute newName and newPath in real-time
  void _applyRulesToPreview() {
    for (var item in _renameItems) {
      final newBase = RenameLogic.applyRules(
        item.baseName,
        _renameRule,
        parentDirName: item.parentDirName,
      );
      item.updateNewName(newBase);
    }
  }

  /// Re-apply rules whenever configuration panel outputs changes
  void _onRulePanelChanged(
    RenameRule rule,
    bool isTargetFile,
    bool isTargetFolder,
    bool recursive,
    String extensionFilter,
  ) {
    setState(() {
      _renameRule = rule;
      if (isTargetFile && isTargetFolder) {
        _renameTarget = RenameTarget.both;
      } else if (isTargetFolder) {
        _renameTarget = RenameTarget.folder;
      } else {
        _renameTarget = RenameTarget.file;
      }
      _recursive = recursive;
      _extensionFilter = extensionFilter;
    });
  }

  /// Trigger directory scanning for Delete
  Future<void> _scanDirectoryForDelete() async {
    if (_selectedDirPath.isEmpty) return;

    setState(() {
      _isDeletingScan = true;
      _deleteScanProgress = 0.0;
      _deleteScanStatus = '开始扫描...';
    });

    final items = await DeleteLogic.scanForDelete(
      rootPath: _selectedDirPath,
      rule: _deleteRule,
      recursive: _deleteRecursive,
      onProgress: (progress, status) {
        if (mounted) {
          setState(() {
            _deleteScanProgress = progress;
            _deleteScanStatus = status;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _deleteItems = items;
        _isDeletingScan = false;
      });
    }
  }

  /// Delete configurations changed callback
  void _onDeleteRulePanelChanged(DeleteFilterRule rule, bool recursive) {
    setState(() {
      _deleteRule = rule;
      _deleteRecursive = recursive;
    });
  }

  /// Trigger directory scanning for Move
  Future<void> _scanDirectoryForMove() async {
    if (_selectedDirPath.isEmpty) return;

    setState(() {
      _isMovingScan = true;
      _moveScanProgress = 0.0;
      _moveScanStatus = '开始扫描...';
    });

    final items = await MoveLogic.scanForMove(
      rootPath: _selectedDirPath,
      rule: _moveRule,
      recursive: _moveRecursive,
      onProgress: (progress, status) {
        if (mounted) {
          setState(() {
            _moveScanProgress = progress;
            _moveScanStatus = status;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _moveItems = items;
        _isMovingScan = false;
      });
    }
  }

  /// Move configurations changed callback
  void _onMoveRulePanelChanged(
    MoveFilterRule rule,
    bool recursive,
    String targetDirPath,
    ConflictStrategy strategy,
  ) {
    setState(() {
      _moveRule = rule;
      _moveRecursive = rule.flattenToRoot ? true : recursive;
      _targetDirPath = rule.flattenToRoot
          ? _selectedDirPath
          : (targetDirPath.isNotEmpty ? targetDirPath : _targetDirPath);
      _conflictStrategy = strategy;
    });
  }

  /// Trigger directory scanning for Sniffer
  Future<void> _scanDirectoryForSniffer() async {
    if (_selectedDirPath.isEmpty) return;

    setState(() {
      _isSnifferScan = true;
      _snifferScanProgress = 0.0;
      _snifferScanStatus = '开始扫描...';
    });

    final items = await SnifferLogic.scanDirectoriesForSniff(
      rootPath: _selectedDirPath,
      rule: _snifferRule,
      onProgress: (progress, status) {
        if (mounted) {
          setState(() {
            _snifferScanProgress = progress;
            _snifferScanStatus = status;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _snifferItems = items;
        _isSnifferScan = false;
      });
    }
  }

  /// Sniffer configurations changed callback
  void _onSnifferRulePanelChanged(SnifferRule rule) {
    final bool needsRescan = rule.recursive != _snifferRule.recursive;
    setState(() {
      _snifferRule = rule;
    });

    if (needsRescan && _selectedDirPath.isNotEmpty) {
      _scanDirectoryForSniffer();
    } else {
      setState(() {
        for (var item in _snifferItems) {
          item.updateNewName(_snifferRule);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobileLayout = screenWidth < 900;

    // Mobile layout Tab controllers setup
    if (isMobileLayout) {
      _mobileRenameTabController ??= TabController(length: 2, vsync: this);
      _mobileDeleteTabController ??= TabController(length: 2, vsync: this);
      _mobileMoveTabController ??= TabController(length: 2, vsync: this);
      _mobileSnifferTabController ??= TabController(length: 2, vsync: this);
    } else {
      _mobileRenameTabController?.dispose();
      _mobileRenameTabController = null;
      _mobileDeleteTabController?.dispose();
      _mobileDeleteTabController = null;
      _mobileMoveTabController?.dispose();
      _mobileMoveTabController = null;
      _mobileSnifferTabController?.dispose();
      _mobileSnifferTabController = null;
    }

    final activeColor = _currentTab == 0
        ? Colors.indigoAccent
        : (_currentTab == 1
            ? Colors.redAccent
            : (_currentTab == 2 ? Colors.orangeAccent : Colors.purpleAccent));

    return Scaffold(
      appBar: isMobileLayout
          ? AppBar(
              backgroundColor: context.cardBg,
              title: Text(
                _currentTab == 0
                    ? '批量重命名'
                    : (_currentTab == 1
                        ? '批量删除'
                        : (_currentTab == 2 ? '批量移动' : '文件嗅探')),
                style: TextStyle(
                    color: context.textColorPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18),
              ),
              actions: [
                IconButton(
                  onPressed: _showSettingsDialog,
                  icon: const Icon(Icons.settings),
                  tooltip: '主题设置',
                  style: IconButton.styleFrom(
                    foregroundColor: context.textColorSecondary,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              elevation: 0,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Divider(
                    color: context.borderColor, height: 1, thickness: 1),
              ),
            )
          : null,
      body: isMobileLayout
          ? _buildMobileView()
          : Row(
              children: [
                Container(
                  color: context.cardBg,
                  child: Column(
                    children: [
                      Expanded(
                        child: NavigationRail(
                          backgroundColor: Colors.transparent,
                          indicatorColor: Colors.transparent,
                          selectedIndex: _currentTab,
                          onDestinationSelected: (int index) {
                            setState(() {
                              _currentTab = index;
                            });
                          },
                          labelType: NavigationRailLabelType.all,
                          selectedLabelTextStyle: TextStyle(
                            color: activeColor,
                            fontWeight: FontWeight.bold,
                          ),
                          unselectedLabelTextStyle:
                              TextStyle(color: context.textColorSecondary),
                          selectedIconTheme: IconThemeData(
                            color: activeColor,
                          ),
                          unselectedIconTheme:
                              IconThemeData(color: context.textColorSecondary),
                          destinations: const [
                            NavigationRailDestination(
                              icon: Icon(Icons.auto_fix_high),
                              selectedIcon: Icon(Icons.auto_fix_high),
                              label: Text('批量重命名'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.delete_sweep),
                              selectedIcon: Icon(Icons.delete_sweep),
                              label: Text('批量删除'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.drive_file_move),
                              selectedIcon: Icon(Icons.drive_file_move),
                              label: Text('批量移动'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.saved_search),
                              selectedIcon: Icon(Icons.saved_search),
                              label: Text('文件嗅探'),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: IconButton(
                          onPressed: _showSettingsDialog,
                          icon: const Icon(Icons.settings, size: 24),
                          tooltip: '主题设置',
                          style: IconButton.styleFrom(
                            foregroundColor: context.textColorSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                VerticalDivider(
                    thickness: 1, width: 1, color: context.borderColor),
                Expanded(
                  child: _buildDesktopView(),
                ),
              ],
            ),
      bottomNavigationBar: isMobileLayout
          ? BottomNavigationBar(
              currentIndex: _currentTab,
              onTap: (int index) {
                setState(() {
                  _currentTab = index;
                });
              },
              backgroundColor: context.cardBg,
              selectedItemColor: activeColor,
              unselectedItemColor: context.textColorSecondary,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.auto_fix_high),
                  label: '批量重命名',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.delete_sweep),
                  label: '批量删除',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.drive_file_move),
                  label: '批量移动',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.saved_search),
                  label: '文件嗅探',
                ),
              ],
            )
          : null,
    );
  }

  /// Windows Large Screen Layout
  Widget _buildDesktopView() {
    if (_currentTab == 0) {
      return _buildRenameDesktopView();
    } else if (_currentTab == 1) {
      return _buildDeleteDesktopView();
    } else if (_currentTab == 2) {
      return _buildMoveDesktopView();
    } else {
      return _buildSnifferDesktopView();
    }
  }

  Widget _buildRenameDesktopView() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Sidebar: Directory Selector & Config Panel
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildDirSelectorCard(),
                  const SizedBox(height: 8),
                  RenameRulePanel(
                    initialRule: _renameRule,
                    initialIsTargetFile: _renameTarget == RenameTarget.file ||
                        _renameTarget == RenameTarget.both,
                    initialIsTargetFolder:
                        _renameTarget == RenameTarget.folder ||
                            _renameTarget == RenameTarget.both,
                    initialRecursive: _recursive,
                    initialExtensionFilter: _extensionFilter,
                    onChanged: _onRulePanelChanged,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Right Main Area: Preview Panel
          Expanded(
            flex: 5,
            child: PreviewPanel(
              items: _renameItems,
              isScanning: _isScanning,
              onRenameStarted: () {},
              onRenameCompleted: _scanDirectory,
              onSearch: _selectedDirPath.isNotEmpty ? _scanDirectory : null,
              onItemSelectionChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteDesktopView() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Sidebar: Directory Selector & Config Panel
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildDirSelectorCard(),
                  const SizedBox(height: 8),
                  DeleteRulePanel(
                    initialRule: _deleteRule,
                    initialRecursive: _deleteRecursive,
                    onChanged: _onDeleteRulePanelChanged,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Right Main Area: Delete Preview Panel
          Expanded(
            flex: 5,
            child: DeletePreviewPanel(
              items: _deleteItems,
              isScanning: _isDeletingScan,
              scanProgress: _deleteScanProgress,
              scanStatus: _deleteScanStatus,
              onDeleteStarted: () {},
              onDeleteCompleted: _scanDirectoryForDelete,
              onSearch:
                  _selectedDirPath.isNotEmpty ? _scanDirectoryForDelete : null,
              onItemSelectionChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoveDesktopView() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Sidebar: Directory Selector & Config Panel
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildDirSelectorCard(),
                  const SizedBox(height: 8),
                  MoveRulePanel(
                    initialRule: _moveRule,
                    initialRecursive: _moveRecursive,
                    initialTargetDirPath: _targetDirPath,
                    initialConflictStrategy: _conflictStrategy,
                    onChanged: _onMoveRulePanelChanged,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Right Main Area: Move Preview Panel
          Expanded(
            flex: 5,
            child: MovePreviewPanel(
              items: _moveItems,
              isScanning: _isMovingScan,
              scanProgress: _moveScanProgress,
              scanStatus: _moveScanStatus,
              sourceDirPath: _selectedDirPath,
              targetDirPath: _targetDirPath,
              rule: _moveRule,
              conflictStrategy: _conflictStrategy,
              onMoveStarted: () {},
              onMoveCompleted: _scanDirectoryForMove,
              onSearch:
                  _selectedDirPath.isNotEmpty ? _scanDirectoryForMove : null,
              onItemSelectionChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileView() {
    if (_currentTab == 0) {
      return _buildRenameMobileView();
    } else if (_currentTab == 1) {
      return _buildDeleteMobileView();
    } else if (_currentTab == 2) {
      return _buildMoveMobileView();
    } else {
      return _buildSnifferMobileView();
    }
  }

  Widget _buildRenameMobileView() {
    final changedCount = _renameItems
        .where((item) =>
            item.isSelected &&
            item.newName != item.baseName &&
            item.newName.isNotEmpty)
        .length;

    return Column(
      children: [
        // Target Dir Selector at Top
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: _buildDirSelectorCard(),
        ),

        // Mobile Tab Bar
        TabBar(
          controller: _mobileRenameTabController,
          labelColor: Colors.indigoAccent,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.indigoAccent,
          tabs: [
            const Tab(text: '规则配置', icon: Icon(Icons.tune)),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('实时预览'),
                  if (changedCount > 0) ...[
                    const SizedBox(width: 6),
                    Badge(
                      label: Text('$changedCount'),
                      backgroundColor: Colors.indigoAccent,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),

        // Tab Content
        Expanded(
          child: TabBarView(
            controller: _mobileRenameTabController,
            children: [
              // Tab 1: Rules Configuration
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: SingleChildScrollView(
                  child: RenameRulePanel(
                    initialRule: _renameRule,
                    initialIsTargetFile: _renameTarget == RenameTarget.file ||
                        _renameTarget == RenameTarget.both,
                    initialIsTargetFolder:
                        _renameTarget == RenameTarget.folder ||
                            _renameTarget == RenameTarget.both,
                    initialRecursive: _recursive,
                    initialExtensionFilter: _extensionFilter,
                    onChanged: _onRulePanelChanged,
                  ),
                ),
              ),

              // Tab 2: Preview Panel
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: PreviewPanel(
                  items: _renameItems,
                  isScanning: _isScanning,
                  onRenameStarted: () {},
                  onRenameCompleted: _scanDirectory,
                  onSearch: _selectedDirPath.isNotEmpty ? _scanDirectory : null,
                  onItemSelectionChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeleteMobileView() {
    final selectedDeleteCount =
        _deleteItems.where((item) => item.isSelected).length;

    return Column(
      children: [
        // Target Dir Selector at Top
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: _buildDirSelectorCard(),
        ),

        // Mobile Tab Bar
        TabBar(
          controller: _mobileDeleteTabController,
          labelColor: Colors.redAccent,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.redAccent,
          tabs: [
            const Tab(text: '过滤配置', icon: Icon(Icons.filter_alt)),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('待删队列'),
                  if (selectedDeleteCount > 0) ...[
                    const SizedBox(width: 6),
                    Badge(
                      label: Text('$selectedDeleteCount'),
                      backgroundColor: Colors.redAccent,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),

        // Tab Content
        Expanded(
          child: TabBarView(
            controller: _mobileDeleteTabController,
            children: [
              // Tab 1: Filters Configuration
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: SingleChildScrollView(
                  child: DeleteRulePanel(
                    initialRule: _deleteRule,
                    initialRecursive: _deleteRecursive,
                    onChanged: _onDeleteRulePanelChanged,
                  ),
                ),
              ),

              // Tab 2: Preview Panel
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: DeletePreviewPanel(
                  items: _deleteItems,
                  isScanning: _isDeletingScan,
                  scanProgress: _deleteScanProgress,
                  scanStatus: _deleteScanStatus,
                  onDeleteStarted: () {},
                  onDeleteCompleted: _scanDirectoryForDelete,
                  onSearch: _selectedDirPath.isNotEmpty
                      ? _scanDirectoryForDelete
                      : null,
                  onItemSelectionChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMoveMobileView() {
    final selectedMoveCount =
        _moveItems.where((item) => item.isSelected).length;

    return Column(
      children: [
        // Target Dir Selector at Top
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: _buildDirSelectorCard(),
        ),

        // Mobile Tab Bar
        TabBar(
          controller: _mobileMoveTabController,
          labelColor: Colors.orangeAccent,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.orangeAccent,
          tabs: [
            const Tab(text: '过滤配置', icon: Icon(Icons.filter_alt)),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('待移队列'),
                  if (selectedMoveCount > 0) ...[
                    const SizedBox(width: 6),
                    Badge(
                      label: Text('$selectedMoveCount'),
                      backgroundColor: Colors.orangeAccent,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),

        // Tab Content
        Expanded(
          child: TabBarView(
            controller: _mobileMoveTabController,
            children: [
              // Tab 1: Filters Configuration
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: SingleChildScrollView(
                  child: MoveRulePanel(
                    initialRule: _moveRule,
                    initialRecursive: _moveRecursive,
                    initialTargetDirPath: _targetDirPath,
                    initialConflictStrategy: _conflictStrategy,
                    onChanged: _onMoveRulePanelChanged,
                  ),
                ),
              ),

              // Tab 2: Preview Panel
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: MovePreviewPanel(
                  items: _moveItems,
                  isScanning: _isMovingScan,
                  scanProgress: _moveScanProgress,
                  scanStatus: _moveScanStatus,
                  sourceDirPath: _selectedDirPath,
                  targetDirPath: _targetDirPath,
                  rule: _moveRule,
                  conflictStrategy: _conflictStrategy,
                  onMoveStarted: () {},
                  onMoveCompleted: _scanDirectoryForMove,
                  onSearch: _selectedDirPath.isNotEmpty
                      ? _scanDirectoryForMove
                      : null,
                  onItemSelectionChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDirSelectorCard() {
    final activeColor = _currentTab == 0
        ? Colors.indigoAccent
        : (_currentTab == 1
            ? Colors.redAccent
            : (_currentTab == 2 ? Colors.orangeAccent : Colors.purpleAccent));

    return Card(
      color: context.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '选择目标文件夹',
              style: TextStyle(
                  color: context.textColorPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: context.inputBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.inputBorderColor),
                    ),
                    child: Text(
                      _selectedDirPath.isEmpty ? '未选择任何目录' : _selectedDirPath,
                      style: TextStyle(
                        color: _selectedDirPath.isEmpty
                            ? context.textColorSecondary
                            : activeColor,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _selectDirectory,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('选择'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: activeColor,
                    foregroundColor: activeColor == Colors.indigoAccent ||
                            activeColor == Colors.purpleAccent
                        ? Colors.white
                        : Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSnifferDesktopView() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Sidebar: Directory Selector & Config Panel
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildDirSelectorCard(),
                  const SizedBox(height: 8),
                  SnifferRulePanel(
                    initialRule: _snifferRule,
                    onChanged: _onSnifferRulePanelChanged,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Right Main Area: Sniffer Preview Panel
          Expanded(
            flex: 5,
            child: SnifferPreviewPanel(
              items: _snifferItems,
              isScanning: _isSnifferScan,
              scanProgress: _snifferScanProgress,
              scanStatus: _snifferScanStatus,
              onRenameCompleted: _scanDirectoryForSniffer,
              rule: _snifferRule,
              onSearch:
                  _selectedDirPath.isNotEmpty ? _scanDirectoryForSniffer : null,
              onSelectDirectory: _selectDirectory,
              onItemSelectionChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSnifferMobileView() {
    final changedCount = _snifferItems
        .where((item) =>
            item.newName != item.currentName &&
            item.newName.isNotEmpty &&
            item.isSelected)
        .length;

    return Column(
      children: [
        // Target Dir Selector at Top
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: _buildDirSelectorCard(),
        ),

        // Mobile Tab Bar
        TabBar(
          controller: _mobileSnifferTabController,
          labelColor: Colors.purpleAccent,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.purpleAccent,
          tabs: [
            const Tab(text: '嗅探配置', icon: Icon(Icons.tune)),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('嗅探结果'),
                  if (changedCount > 0) ...[
                    const SizedBox(width: 6),
                    Badge(
                      label: Text('$changedCount'),
                      backgroundColor: Colors.purpleAccent,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),

        // Tab Content
        Expanded(
          child: TabBarView(
            controller: _mobileSnifferTabController,
            children: [
              // Tab 1: Rules Configuration
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: SingleChildScrollView(
                  child: SnifferRulePanel(
                    initialRule: _snifferRule,
                    onChanged: _onSnifferRulePanelChanged,
                  ),
                ),
              ),

              // Tab 2: Preview Panel
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: SnifferPreviewPanel(
                  items: _snifferItems,
                  isScanning: _isSnifferScan,
                  scanProgress: _snifferScanProgress,
                  scanStatus: _snifferScanStatus,
                  onRenameCompleted: _scanDirectoryForSniffer,
                  rule: _snifferRule,
                  onSearch: _selectedDirPath.isNotEmpty
                      ? _scanDirectoryForSniffer
                      : null,
                  onSelectDirectory: _selectDirectory,
                  onItemSelectionChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
