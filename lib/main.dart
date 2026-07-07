import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

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

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DocTool - 重复操作解决助手',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Colors.indigoAccent,
          secondary: Colors.purpleAccent,
          surface: Color(0xFF121214),
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0F12),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF16161A),
          elevation: 0,
        ),
      ),
      home: const MainDashboard(),
    );
  }
}

class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> with TickerProviderStateMixin {
  String _selectedDirPath = '';
  int _currentTab = 0; // 0 for Rename, 1 for Delete

  // --- Rename States ---
  RenameRule _renameRule = RenameRule();
  bool _isFileTarget = true;
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
  }

  @override
  void dispose() {
    _mobileRenameTabController?.dispose();
    _mobileDeleteTabController?.dispose();
    _mobileMoveTabController?.dispose();
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
        });
      }
    } else {
      // Windows
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: _currentTab == 0 ? '选择要重命名的文件夹' : '选择要清理的文件夹',
      );
      
      if (path != null && path.isNotEmpty) {
        setState(() {
          _selectedDirPath = path;
        });
      }
    }
  }

  void _showPermissionRequiredDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E22),
        title: const Text('需要存储管理权限', style: TextStyle(color: Colors.white)),
        content: const Text(
          '在 Android 11 及以上版本中，软件需要“所有文件访问权限”才能遍历外部文件夹并执行高速文件操作。请在接下来的设置中开启此权限。',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigoAccent),
            child: const Text('去设置授权', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Trigger scanning based on active tab
  void _scanCurrentTabDir() {
    if (_currentTab == 0) {
      _scanDirectory();
    } else if (_currentTab == 1) {
      _scanDirectoryForDelete();
    } else {
      _scanDirectoryForMove();
    }
  }

  /// Trigger directory scanning for Rename
  Future<void> _scanDirectory() async {
    if (_selectedDirPath.isEmpty) return;

    setState(() {
      _isScanning = true;
    });

    final items = await FileHelper.scanDirectory(
      rootPath: _selectedDirPath,
      isFileTarget: _isFileTarget,
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
    bool isFileTarget,
    bool recursive,
    String extensionFilter,
  ) {
    setState(() {
      _renameRule = rule;
      _isFileTarget = isFileTarget;
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
      _moveRecursive = recursive;
      _targetDirPath = targetDirPath;
      _conflictStrategy = strategy;
    });
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
    } else {
      _mobileRenameTabController?.dispose();
      _mobileRenameTabController = null;
      _mobileDeleteTabController?.dispose();
      _mobileDeleteTabController = null;
      _mobileMoveTabController?.dispose();
      _mobileMoveTabController = null;
    }

    final activeColor = _currentTab == 0 
        ? Colors.indigoAccent 
        : (_currentTab == 1 ? Colors.redAccent : Colors.orangeAccent);

    return Scaffold(
      body: isMobileLayout
          ? _buildMobileView()
          : Row(
              children: [
                NavigationRail(
                  backgroundColor: const Color(0xFF16161A),
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
                  unselectedLabelTextStyle: const TextStyle(color: Colors.grey),
                  selectedIconTheme: IconThemeData(
                    color: activeColor,
                  ),
                  unselectedIconTheme: const IconThemeData(color: Colors.grey),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.auto_fix_high),
                      label: Text('批量重命名'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.delete_sweep),
                      label: Text('批量删除'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.drive_file_move),
                      label: Text('批量移动'),
                    ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1, color: Color(0xFF232329)),
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
              backgroundColor: const Color(0xFF16161A),
              selectedItemColor: activeColor,
              unselectedItemColor: Colors.grey,
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
    } else {
      return _buildMoveDesktopView();
    }
  }

  Widget _buildRenameDesktopView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
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
                  const SizedBox(height: 12),
                  RenameRulePanel(
                    initialRule: _renameRule,
                    initialIsFileTarget: _isFileTarget,
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteDesktopView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
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
                  const SizedBox(height: 12),
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
              onSearch: _selectedDirPath.isNotEmpty ? _scanDirectoryForDelete : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoveDesktopView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
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
                  const SizedBox(height: 12),
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
              onSearch: _selectedDirPath.isNotEmpty ? _scanDirectoryForMove : null,
            ),
          ),
        ],
      ),
    );
  }

  /// Android / Mobile Layout
  Widget _buildMobileView() {
    if (_currentTab == 0) {
      return _buildRenameMobileView();
    } else if (_currentTab == 1) {
      return _buildDeleteMobileView();
    } else {
      return _buildMoveMobileView();
    }
  }

  Widget _buildRenameMobileView() {
    final changedCount = _renameItems.where((item) => item.newName != item.baseName && item.newName.isNotEmpty).length;

    return Column(
      children: [
        // Target Dir Selector at Top
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
                padding: const EdgeInsets.all(16.0),
                child: SingleChildScrollView(
                  child: RenameRulePanel(
                    initialRule: _renameRule,
                    initialIsFileTarget: _isFileTarget,
                    initialRecursive: _recursive,
                    initialExtensionFilter: _extensionFilter,
                    onChanged: _onRulePanelChanged,
                  ),
                ),
              ),
              
              // Tab 2: Preview Panel
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: PreviewPanel(
                  items: _renameItems,
                  isScanning: _isScanning,
                  onRenameStarted: () {},
                  onRenameCompleted: _scanDirectory,
                  onSearch: _selectedDirPath.isNotEmpty ? _scanDirectory : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeleteMobileView() {
    final selectedDeleteCount = _deleteItems.where((item) => item.isSelected).length;

    return Column(
      children: [
        // Target Dir Selector at Top
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
                padding: const EdgeInsets.all(16.0),
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
                padding: const EdgeInsets.all(16.0),
                child: DeletePreviewPanel(
                  items: _deleteItems,
                  isScanning: _isDeletingScan,
                  scanProgress: _deleteScanProgress,
                  scanStatus: _deleteScanStatus,
                  onDeleteStarted: () {},
                  onDeleteCompleted: _scanDirectoryForDelete,
                  onSearch: _selectedDirPath.isNotEmpty ? _scanDirectoryForDelete : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMoveMobileView() {
    final selectedMoveCount = _moveItems.where((item) => item.isSelected).length;

    return Column(
      children: [
        // Target Dir Selector at Top
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
                padding: const EdgeInsets.all(16.0),
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
                padding: const EdgeInsets.all(16.0),
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
                  onSearch: _selectedDirPath.isNotEmpty ? _scanDirectoryForMove : null,
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
        : (_currentTab == 1 ? Colors.redAccent : Colors.orangeAccent);

    return Card(
      color: const Color(0xFF16161A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF232329)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择目标文件夹',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E22),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2C2C35)),
                    ),
                    child: Text(
                      _selectedDirPath.isEmpty ? '未选择任何目录' : _selectedDirPath,
                      style: TextStyle(
                        color: _selectedDirPath.isEmpty ? Colors.grey : activeColor,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (_selectedDirPath.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _scanCurrentTabDir,
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: '重新扫描目录',
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.grey[400],
                      hoverColor: Colors.white10,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _selectDirectory,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('选择'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: activeColor,
                    foregroundColor: activeColor == Colors.indigoAccent ? Colors.white : Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
