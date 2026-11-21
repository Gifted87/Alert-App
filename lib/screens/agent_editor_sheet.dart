import 'package:flutter/material.dart';

import '../models/ai_models.dart';
import '../services/strategy_storage.dart';

class AgentEditorSheet extends StatefulWidget {
  final SpecialistAgentConfig? existingAgent;
  final TradingStrategy? associatedStrategy;
  final List<TradingStrategy> availableStrategies;
  final VoidCallback? onAgentSaved;
  final VoidCallback? onAgentDeleted;

  const AgentEditorSheet({
    super.key,
    this.existingAgent,
    this.associatedStrategy,
    this.availableStrategies = const [],
    this.onAgentSaved,
    this.onAgentDeleted,
  });

  @override
  State<AgentEditorSheet> createState() => _AgentEditorSheetState();
}

class _AgentEditorSheetState extends State<AgentEditorSheet> {
  late TextEditingController _nameController;
  late TextEditingController _promptController;
  late TextEditingController _consolidatorController;

  late double _creativity;
  late String _selectedColorHex;
  late String _selectedIcon;
  late List<String> _selectedTimeframes;
  String? _selectedStrategyId;
  bool _isStandalone = false;

  final List<String> _availableColors = [
    '#30D158', // Green
    '#BF5AF2', // Purple
    '#FFD60A', // Yellow
    '#64D2FF', // Cyan
    '#FF9F0A', // Orange
  ];

  final List<String> _allTimeframes = ['5m', '15m', '1H', '4H', '1D'];

  final List<Map<String, dynamic>> _availableIcons = [
    {'id': 'chart', 'icon': Icons.bar_chart_rounded},
    {'id': 'layers', 'icon': Icons.layers_rounded},
    {'id': 'waves', 'icon': Icons.waves_rounded},
    {'id': 'compass', 'icon': Icons.explore_rounded},
    {'id': 'shield', 'icon': Icons.shield_rounded},
    {'id': 'target', 'icon': Icons.track_changes_rounded},
    {'id': 'activity', 'icon': Icons.show_chart_rounded},
    {'id': 'grid', 'icon': Icons.grid_view_rounded},
  ];

  @override
  void initState() {
    super.initState();
    final agent = widget.existingAgent;
    _nameController = TextEditingController(
      text: agent?.name ?? 'New Specialist',
    );
    _promptController = TextEditingController(
      text: agent?.systemPrompt ?? 'You are a market specialist. Analyze the supplied OHLC candlestick data, identify high-probability structure, and output an exact trade setup with precise entry, stop loss, and take profit.',
    );
    _consolidatorController = TextEditingController(
      text: widget.associatedStrategy?.consolidatorInstructions ?? '',
    );

    _creativity = agent?.creativity ?? 0.2;
    _selectedColorHex = agent?.colorHex ?? '#30D158';
    _selectedIcon = agent?.icon ?? 'chart';
    _selectedTimeframes = agent != null
        ? List<String>.from(agent.timeframes)
        : ['15m', '1H'];
    _selectedStrategyId = widget.associatedStrategy?.id ?? agent?.strategyId;
    _isStandalone =
        _selectedStrategyId == null || _selectedStrategyId == 'standalone';

    _promptController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    _consolidatorController.dispose();
    super.dispose();
  }

  Color _parseColor(String hex) {
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('0xFF$clean'));
    } catch (_) {
      return const Color(0xFF30D158);
    }
  }

  IconData _getIconData(String id) {
    final found = _availableIcons.firstWhere(
      (i) => i['id'] == id,
      orElse: () => _availableIcons.first,
    );
    return found['icon'] as IconData;
  }

  void _save() async {
    final name = _nameController.text.trim();
    final prompt = _promptController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agent name cannot be empty')),
      );
      return;
    }

    final agent = SpecialistAgentConfig(
      id:
          widget.existingAgent?.id ??
          'specialist_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      systemPrompt: prompt,
      icon: _selectedIcon,
      colorHex: _selectedColorHex,
      creativity: _creativity,
      timeframes: _selectedTimeframes.isEmpty
          ? ['15m', '1H']
          : _selectedTimeframes,
      strategyId: _isStandalone ? 'standalone' : _selectedStrategyId,
      description: widget.existingAgent?.description ?? '',
    );

    // Save specialist
    await StrategyStorage().saveSpecialist(agent);

    // If associated with a strategy and custom instructions modified, update strategy
    if (!_isStandalone &&
        _selectedStrategyId != null &&
        _selectedStrategyId != 'standalone') {
      final strats = await StrategyStorage().getStrategies();
      final idx = strats.indexWhere((s) => s.id == _selectedStrategyId);
      if (idx != -1) {
        final strat = strats[idx];
        final specList = List<SpecialistAgentConfig>.from(strat.specialists);
        final specIdx = specList.indexWhere((s) => s.id == agent.id);
        if (specIdx != -1) {
          specList[specIdx] = agent;
        } else {
          specList.add(agent);
        }

        final updatedStrat = strat.copyWith(
          specialists: specList,
          consolidatorInstructions: _consolidatorController.text.trim(),
        );
        await StrategyStorage().saveStrategy(updatedStrat);
      }
    }

    widget.onAgentSaved?.call();
    if (mounted) Navigator.pop(context, agent);
  }

  void _delete() async {
    if (widget.existingAgent == null) {
      Navigator.pop(context);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text(
          'Delete Agent?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete "${widget.existingAgent!.name}"?',
          style: const TextStyle(color: Color(0x99EBEBF5)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF4DA3FF)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Color(0xFFFF453A),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await StrategyStorage().deleteSpecialist(widget.existingAgent!.id);
      widget.onAgentDeleted?.call();
      if (mounted) Navigator.pop(context);
    }
  }

  void _showStrategyPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Select Strategy Mode',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.person_rounded,
                  color: Color(0xFF30D158),
                ),
                title: const Text(
                  'Standalone Specialist',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Can be run on its own with Grounding Critic',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: _isStandalone
                    ? const Icon(Icons.check, color: Color(0xFF30D158))
                    : null,
                onTap: () {
                  setState(() {
                    _isStandalone = true;
                    _selectedStrategyId = 'standalone';
                  });
                  Navigator.pop(ctx);
                },
              ),
              const Divider(color: Color(0x17FFFFFF), height: 1),
              ...widget.availableStrategies.map((strat) {
                final isSelected =
                    !_isStandalone && _selectedStrategyId == strat.id;
                return ListTile(
                  leading: const Icon(
                    Icons.hub_rounded,
                    color: Color(0xFFBF5AF2),
                  ),
                  title: Text(
                    strat.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    'Multi-agent strategy (${strat.specialists.length} specialists)',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check, color: Color(0xFFBF5AF2))
                      : null,
                  onTap: () {
                    setState(() {
                      _isStandalone = false;
                      _selectedStrategyId = strat.id;
                      _consolidatorController.text =
                          strat.consolidatorInstructions;
                    });
                    Navigator.pop(ctx);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showIconPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Choose Agent Icon',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: _availableIcons.map((i) {
                    final id = i['id'] as String;
                    final iconData = i['icon'] as IconData;
                    final isSel = _selectedIcon == id;
                    return InkWell(
                      onTap: () {
                        setState(() => _selectedIcon = id);
                        Navigator.pop(ctx);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: isSel
                              ? _parseColor(_selectedColorHex)
                                    .withValues(alpha: 0.25)
                              : const Color(0xFF2C2C2E),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSel
                                ? _parseColor(_selectedColorHex)
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          iconData,
                          color: isSel
                              ? _parseColor(_selectedColorHex)
                              : Colors.white70,
                          size: 28,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = _parseColor(_selectedColorHex);
    final activeIconData = _getIconData(_selectedIcon);

    String strategyDisplayName = 'Standalone Agent';
    if (!_isStandalone && _selectedStrategyId != null) {
      final found = widget.availableStrategies.firstWhere(
        (s) => s.id == _selectedStrategyId,
        orElse: () => TradingStrategy(
          id: '',
          name: 'Multi-Agent Strategy',
          specialists: [],
          createdAt: DateTime.now(),
        ),
      );
      if (found.name.isNotEmpty) strategyDisplayName = found.name;
    }

    final topPadding = MediaQuery.of(context).padding.top;
    final screenHeight = MediaQuery.of(context).size.height;
    final maxSheetHeight = screenHeight - topPadding - 32;

    return Container(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      margin: EdgeInsets.only(top: topPadding + 16),
      decoration: const BoxDecoration(
        color: Color(0xFF141416),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0x33FFFFFF), width: 1)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Column(
          children: [
            // Grab handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0x4DEBEBF5),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
            // Header: Cancel · Edit Agent · Save (exact match to AgentEditor.dc.html)
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 17,
                        color: Color(0xFF4DA3FF),
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                  Text(
                    widget.existingAgent != null ? 'Edit Agent' : 'New Agent',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  GestureDetector(
                    onTap: _save,
                    child: const Text(
                      'Save',
                      style: TextStyle(
                        fontSize: 17,
                        color: Color(0xFF4DA3FF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hero Icon (64x64, rounded 20px)
                    Center(
                      child: GestureDetector(
                        onTap: _showIconPicker,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: activeColor.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            activeIconData,
                            color: activeColor,
                            size: 30,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Color Rings (Green, Purple, Yellow, Cyan, Orange)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _availableColors.map((hex) {
                        final color = _parseColor(hex);
                        final isSelected =
                            _selectedColorHex.toUpperCase() ==
                            hex.toUpperCase();
                        return GestureDetector(
                          onTap: () => setState(() => _selectedColorHex = hex),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 5),
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              boxShadow: isSelected
                                  ? [
                                      const BoxShadow(
                                        color: Colors.black,
                                        spreadRadius: 2,
                                      ),
                                      BoxShadow(color: color, spreadRadius: 4),
                                    ]
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),

                    // SECTION: NAME
                    _buildSectionHeader('NAME'),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TextField(
                        controller: _nameController,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          hintText: 'Agent Name',
                          hintStyle: TextStyle(color: Color(0x55EBEBF5)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // SECTION: SYSTEM PROMPT
                    _buildSectionHeader('SYSTEM PROMPT'),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _promptController,
                            maxLines: 7,
                            minLines: 4,
                            maxLength: 2000,
                            buildCounter: (
                              ctx, {
                              required currentLength,
                              required isFocused,
                              maxLength,
                            }) => null,
                            style: const TextStyle(
                              color: Color(0xE0FFFFFF),
                              fontSize: 14,
                              height: 1.5,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              hintText:
                                  'Enter domain specialist instructions...',
                              hintStyle: TextStyle(color: Color(0x55EBEBF5)),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_promptController.text.length} / 2000',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: Color(0x57EBEBF5),
                                ),
                              ),
                              Container(
                                height: 22,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0x2464D2FF),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: const Center(
                                  child: Text(
                                    'Returns strict JSON',
                                    style: TextStyle(
                                      color: Color(0xFF64D2FF),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // SECTION: TIMEFRAMES
                    _buildSectionHeader('TIMEFRAMES'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _allTimeframes.map((tf) {
                          final isSelected = _selectedTimeframes.contains(tf);
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  if (_selectedTimeframes.length > 1) {
                                    _selectedTimeframes.remove(tf);
                                  }
                                } else {
                                  _selectedTimeframes.add(tf);
                                }
                              });
                            },
                            child: Container(
                              height: 32,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0x38BF5AF2)
                                    : const Color(0xFF2C2C2E),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Center(
                                child: Text(
                                  tf,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? const Color(0xFFD58CF7)
                                        : const Color(0x9EEBEBF5),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // SECTION: STRATEGY & CREATIVITY
                    _buildSectionHeader('STRATEGY & CREATIVITY'),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          // Strategy selector row
                          InkWell(
                            onTap: _showStrategyPicker,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(20),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Strategy Mode',
                                      style: TextStyle(
                                        fontSize: 17,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    strategyDisplayName,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      color: Color(0x9EEBEBF5),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: Color(0x57EBEBF5),
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Divider(color: Color(0x17FFFFFF), height: 1),

                          // Creativity Slider row
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Creativity',
                                      style: TextStyle(
                                        fontSize: 17,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      _creativity.toStringAsFixed(2),
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 15,
                                        color: Color(0x9EEBEBF5),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: const Color(0xFFBF5AF2),
                                    inactiveTrackColor: const Color(0xFF3A3A3C),
                                    thumbColor: Colors.white,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 10,
                                    ),
                                    overlayColor: const Color(0x29BF5AF2),
                                    trackHeight: 4,
                                  ),
                                  child: Slider(
                                    value: _creativity,
                                    min: 0.0,
                                    max: 1.0,
                                    onChanged: (val) {
                                      setState(() => _creativity = val);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // SECTION: CONSOLIDATOR INSTRUCTIONS (App capability for multi-agent)
                    if (!_isStandalone) ...[
                      const SizedBox(height: 18),
                      _buildSectionHeader('CONSOLIDATOR DIRECTIVES'),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Custom instructions given to the Consolidator Officer when synthesizing all specialists into the final signal:',
                              style: TextStyle(
                                color: Color(0x9EEBEBF5),
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _consolidatorController,
                              maxLines: 3,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                hintText: 'e.g. Prioritize SMC order blocks over Wyckoff if timeframes conflict...',
                                hintStyle: TextStyle(color: Color(0x55EBEBF5)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 32),

                    // DELETE AGENT BUTTON
                    if (widget.existingAgent != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: TextButton(
                            onPressed: _delete,
                            style: TextButton.styleFrom(
                              backgroundColor: const Color(0x29FF453A),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            child: const Text(
                              'Delete Agent',
                              style: TextStyle(
                                color: Color(0xFFFF6961),
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 32, right: 32, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.09 * 11,
          color: Color(0x9EEBEBF5),
        ),
      ),
    );
  }
}
