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

class _MainDashboardState extends State<MainDashboard> with SingleTickerProviderStateMixin {
  String _selectedDirPath = '';
  RenameRule _rule = RenameRule();
  bool _isFileTarget = true;
  bool _recursive = false;
  String _extensionFilter = '';
  
  bool _isScanning = false;
  List<RenameItem> _renameItems = [];
  
  TabController? _mobileTabController;

  @override
  void initState() {
    super.initState();
    // Default initial rule
    _rule = RenameRule(
      insertRule: InsertRule(),
      deleteRule: DeleteRule(),
      parentDirRule: ParentDirRule(),
    );
  }

  @override
  void dispose() {
    _mobileTabController?.dispose();
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
        _scanDirectory();
      }
    } else {
      // Windows
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择要重命名的文件夹',
      );
      
      if (path != null && path.isNotEmpty) {
        setState(() {
          _selectedDirPath = path;
        });
        _scanDirectory();
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
          '在 Android 11 及以上版本中，软件需要“所有文件访问权限”才能遍历外部文件夹并执行高速重命名操作。请在接下来的设置中开启此权限。',
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

  /// Trigger directory scanning and apply current rules immediately
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
        _rule,
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
    final targetChanged = _isFileTarget != isFileTarget;
    final recursiveChanged = _recursive != recursive;
    final filterChanged = _extensionFilter != extensionFilter;

    setState(() {
      _rule = rule;
      _isFileTarget = isFileTarget;
      _recursive = recursive;
      _extensionFilter = extensionFilter;
    });

    if (targetChanged || recursiveChanged || filterChanged) {
      // Re-scan directory since target filters changed
      _scanDirectory();
    } else {
      // Just re-calculate preview names without hitting the disk
      setState(() {
        _applyRulesToPreview();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobileLayout = screenWidth < 900;

    // Mobile layout Tab setup
    if (isMobileLayout && _mobileTabController == null) {
      _mobileTabController = TabController(length: 2, vsync: this);
    } else if (!isMobileLayout && _mobileTabController != null) {
      _mobileTabController?.dispose();
      _mobileTabController = null;
    }

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.indigo, Colors.purple],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Row(
          children: [
            Icon(Icons.auto_fix_high, color: Colors.white),
            SizedBox(width: 10),
            Text(
              'DocTool - 批量重命名',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        actions: [
          if (_selectedDirPath.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: '重新扫描目录',
              onPressed: _scanDirectory,
            ),
        ],
      ),
      body: isMobileLayout ? _buildMobileView() : _buildDesktopView(),
    );
  }

  /// Windows Large Screen Layout
  Widget _buildDesktopView() {
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
                  const SizedBox(height: 16),
                  RenameRulePanel(
                    initialRule: _rule,
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
            ),
          ),
        ],
      ),
    );
  }

  /// Android / Mobile Layout
  Widget _buildMobileView() {
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
          controller: _mobileTabController,
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
            controller: _mobileTabController,
            children: [
              // Tab 1: Rules Configuration
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SingleChildScrollView(
                  child: RenameRulePanel(
                    initialRule: _rule,
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
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDirSelectorCard() {
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '选择目标文件夹',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                ElevatedButton.icon(
                  onPressed: _selectDirectory,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('选择'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2C2C35),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1E1E22)),
              ),
              child: Text(
                _selectedDirPath.isEmpty ? '未选择任何目录' : _selectedDirPath,
                style: TextStyle(
                  color: _selectedDirPath.isEmpty ? Colors.grey : Colors.indigoAccent[100],
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
