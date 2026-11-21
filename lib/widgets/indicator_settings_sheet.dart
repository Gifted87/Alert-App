import 'package:flutter/material.dart';

import '../models/indicator_models.dart';
import '../theme/app_theme.dart';

class IndicatorSettingsSheet extends StatefulWidget {
  final IndicatorConfig config;
  final ValueChanged<IndicatorConfig> onSave;

  const IndicatorSettingsSheet({
    super.key,
    required this.config,
    required this.onSave,
  });

  static Future<void> show(
    BuildContext context, {
    required IndicatorConfig config,
    required ValueChanged<IndicatorConfig> onSave,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => IndicatorSettingsSheet(config: config, onSave: onSave),
    );
  }

  @override
  State<IndicatorSettingsSheet> createState() => _IndicatorSettingsSheetState();
}

class _IndicatorSettingsSheetState extends State<IndicatorSettingsSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late IndicatorConfig _editingConfig;

  // Preset vibrant palette colors for trading charts
  static const List<Color> _palette = [
    Color(0xFF00E5FF), // Electric Cyan
    Color(0xFF26A69A), // Teal / Green
    Color(0xFFFFEB3B), // Bright Yellow
    Color(0xFFFF9800), // Amber / Orange
    Color(0xFFAB47BC), // Purple
    Color(0xFFEF5350), // Coral Red
    Color(0xFF2962FF), // Royal Blue
    Color(0xFFFFFFFF), // Crisp White
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _editingConfig = widget.config.copyWith();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bg = isDark ? AppTheme.darkSurface1 : Colors.white;
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final textSecondary = isDark ? Colors.white60 : Colors.black54;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    _editingConfig.type.shortName,
                    style: const TextStyle(
                      color: Color(0xFF00E5FF),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_editingConfig.type.fullName} Settings',
                    style: TextStyle(
                      color: textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: textSecondary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Tab Bar (Inputs & Style - TradingView standard)
          TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFF00E5FF),
            labelColor: const Color(0xFF00E5FF),
            unselectedLabelColor: textSecondary,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            tabs: const [
              Tab(text: 'Inputs'),
              Tab(text: 'Style'),
            ],
          ),
          Divider(height: 1, color: borderColor),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildInputsTab(
                  isDark,
                  textPrimary,
                  textSecondary,
                  borderColor,
                ),
                _buildStyleTab(isDark, textPrimary, textSecondary, borderColor),
              ],
            ),
          ),

          // Bottom Action Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: borderColor)),
              color: isDark ? AppTheme.darkSurface2 : const Color(0xFFF9F9F9),
            ),
            child: Row(
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _editingConfig = IndicatorConfig.defaultFor(
                        _editingConfig.type,
                      );
                    });
                  },
                  child: Text(
                    'Reset Defaults',
                    style: TextStyle(color: textSecondary, fontSize: 13),
                  ),
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: borderColor),
                  ),
                  child: Text('Cancel', style: TextStyle(color: textPrimary)),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () {
                    widget.onSave(_editingConfig);
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  child: const Text('Apply Changes'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputsTab(
    bool isDark,
    Color textPrimary,
    Color textSecondary,
    Color borderColor,
  ) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        if (_editingConfig.type == IndicatorType.rsi) ...[
          _buildNumericRow(
            'Length (Period)',
            'period',
            14,
            2,
            100,
            1,
            textPrimary,
            textSecondary,
          ),
          const SizedBox(height: 16),
          _buildNumericRow(
            'Overbought Level',
            'overbought',
            70.0,
            50.0,
            95.0,
            1.0,
            textPrimary,
            textSecondary,
          ),
          const SizedBox(height: 16),
          _buildNumericRow(
            'Oversold Level',
            'oversold',
            30.0,
            5.0,
            50.0,
            1.0,
            textPrimary,
            textSecondary,
          ),
        ] else if (_editingConfig.type == IndicatorType.macd) ...[
          _buildNumericRow(
            'Fast Length',
            'fastPeriod',
            12,
            2,
            50,
            1,
            textPrimary,
            textSecondary,
          ),
          const SizedBox(height: 16),
          _buildNumericRow(
            'Slow Length',
            'slowPeriod',
            26,
            5,
            100,
            1,
            textPrimary,
            textSecondary,
          ),
          const SizedBox(height: 16),
          _buildNumericRow(
            'Signal Smoothing',
            'signalPeriod',
            9,
            2,
            50,
            1,
            textPrimary,
            textSecondary,
          ),
        ] else if (_editingConfig.type == IndicatorType.stochastic) ...[
          _buildNumericRow(
            '%K Length',
            'kPeriod',
            14,
            2,
            50,
            1,
            textPrimary,
            textSecondary,
          ),
          const SizedBox(height: 16),
          _buildNumericRow(
            '%D Smoothing',
            'dPeriod',
            3,
            1,
            20,
            1,
            textPrimary,
            textSecondary,
          ),
          const SizedBox(height: 16),
          _buildNumericRow(
            'Slowing',
            'smooth',
            3,
            1,
            20,
            1,
            textPrimary,
            textSecondary,
          ),
          const SizedBox(height: 16),
          _buildNumericRow(
            'Overbought',
            'overbought',
            80.0,
            60.0,
            95.0,
            1.0,
            textPrimary,
            textSecondary,
          ),
          const SizedBox(height: 16),
          _buildNumericRow(
            'Oversold',
            'oversold',
            20.0,
            5.0,
            40.0,
            1.0,
            textPrimary,
            textSecondary,
          ),
        ] else if (_editingConfig.type == IndicatorType.ema ||
            _editingConfig.type == IndicatorType.sma) ...[
          _buildNumericRow(
            'Length (Period)',
            'period',
            20,
            2,
            500,
            1,
            textPrimary,
            textSecondary,
          ),
        ] else if (_editingConfig.type == IndicatorType.bollingerBands) ...[
          _buildNumericRow(
            'Length (Period)',
            'period',
            20,
            2,
            200,
            1,
            textPrimary,
            textSecondary,
          ),
          const SizedBox(height: 16),
          _buildNumericRow(
            'StdDev Multiplier',
            'stdDev',
            2.0,
            0.5,
            5.0,
            0.1,
            textPrimary,
            textSecondary,
          ),
        ] else if (_editingConfig.type == IndicatorType.supertrend) ...[
          _buildNumericRow(
            'ATR Length (Period)',
            'period',
            10,
            1,
            100,
            1,
            textPrimary,
            textSecondary,
          ),
          const SizedBox(height: 16),
          _buildNumericRow(
            'Multiplier (Factor)',
            'multiplier',
            3.0,
            0.5,
            10.0,
            0.1,
            textPrimary,
            textSecondary,
          ),
        ],
      ],
    );
  }

  Widget _buildNumericRow(
    String title,
    String key,
    num defaultVal,
    num minVal,
    num maxVal,
    num step,
    Color textPrimary,
    Color textSecondary,
  ) {
    final currentVal = _editingConfig.inputs[key] is num
        ? _editingConfig.inputs[key] as num
        : defaultVal;
    final isDouble = defaultVal is double;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                'Min: $minVal, Max: $maxVal',
                style: TextStyle(color: textSecondary, fontSize: 11),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove, size: 16),
                color: const Color(0xFF00E5FF),
                onPressed: () {
                  final next = currentVal - step;
                  if (next >= minVal) {
                    setState(() {
                      _editingConfig.inputs[key] = isDouble
                          ? double.parse(next.toStringAsFixed(1))
                          : next.round();
                    });
                  }
                },
              ),
              Container(
                constraints: const BoxConstraints(minWidth: 44),
                alignment: Alignment.center,
                child: Text(
                  isDouble
                      ? currentVal.toStringAsFixed(1)
                      : currentVal.toInt().toString(),
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 16),
                color: const Color(0xFF00E5FF),
                onPressed: () {
                  final next = currentVal + step;
                  if (next <= maxVal) {
                    setState(() {
                      _editingConfig.inputs[key] = isDouble
                          ? double.parse(next.toStringAsFixed(1))
                          : next.round();
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStyleTab(
    bool isDark,
    Color textPrimary,
    Color textSecondary,
    Color borderColor,
  ) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        // Visibility toggle
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Show Indicator',
              style: TextStyle(color: textPrimary, fontWeight: FontWeight.w500),
            ),
            Switch(
              value: _editingConfig.isVisible,
              activeThumbColor: const Color(0xFF00E5FF),
              onChanged: (val) =>
                  setState(() => _editingConfig.isVisible = val),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Line width selector
        Text(
          'Line Thickness',
          style: TextStyle(color: textPrimary, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Row(
          children: [1.0, 1.8, 2.5, 3.5].map((w) {
            final isSelected = (_editingConfig.lineWidth - w).abs() < 0.2;
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ChoiceChip(
                label: Text('${w.toStringAsFixed(1)}px'),
                selected: isSelected,
                selectedColor: const Color(0xFF00E5FF).withValues(alpha: 0.25),
                backgroundColor: isDark
                    ? AppTheme.darkSurface2
                    : const Color(0xFFF0F0F0),
                labelStyle: TextStyle(
                  color: isSelected ? const Color(0xFF00E5FF) : textPrimary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
                onSelected: (_) => setState(() => _editingConfig.lineWidth = w),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // Color Selectors
        if (_editingConfig.type == IndicatorType.rsi) ...[
          _buildColorPickerSection(
            'RSI Line Color',
            'main',
            const Color(0xFFAB47BC),
            textPrimary,
          ),
        ] else if (_editingConfig.type == IndicatorType.macd) ...[
          _buildColorPickerSection(
            'MACD Line Color',
            'macd',
            const Color(0xFF2962FF),
            textPrimary,
          ),
          const SizedBox(height: 16),
          _buildColorPickerSection(
            'Signal Line Color',
            'signal',
            const Color(0xFFFF6D00),
            textPrimary,
          ),
        ] else if (_editingConfig.type == IndicatorType.stochastic) ...[
          _buildColorPickerSection(
            '%K Line Color',
            'k',
            const Color(0xFF2196F3),
            textPrimary,
          ),
          const SizedBox(height: 16),
          _buildColorPickerSection(
            '%D Line Color',
            'd',
            const Color(0xFFFF9800),
            textPrimary,
          ),
        ] else if (_editingConfig.type == IndicatorType.bollingerBands) ...[
          _buildColorPickerSection(
            'Bands Color (Upper/Lower)',
            'upper',
            const Color(0xFF00E5FF),
            textPrimary,
            onColorChosen: (c) {
              _editingConfig.setColor('upper', c);
              _editingConfig.setColor('lower', c);
              _editingConfig.setColor('fill', c.withValues(alpha: 0.12));
            },
          ),
          const SizedBox(height: 16),
          _buildColorPickerSection(
            'Basis Line (SMA) Color',
            'basis',
            const Color(0xFFFF9800),
            textPrimary,
          ),
        ] else ...[
          _buildColorPickerSection(
            'Plot Color',
            'main',
            const Color(0xFF00E5FF),
            textPrimary,
          ),
        ],
      ],
    );
  }

  Widget _buildColorPickerSection(
    String label,
    String colorKey,
    Color defaultColor,
    Color textPrimary, {
    ValueChanged<Color>? onColorChosen,
  }) {
    final currentColor = _editingConfig.getColor(colorKey, defaultColor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: currentColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white70, width: 1.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: _palette.map((c) {
            final isSelected = currentColor.toARGB32() == c.toARGB32();
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (onColorChosen != null) {
                    onColorChosen(c);
                  } else {
                    _editingConfig.setColor(colorKey, c);
                  }
                });
              },
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.transparent,
                    width: isSelected ? 2.5 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: c.withValues(alpha: 0.6),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 16, color: Colors.black)
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
