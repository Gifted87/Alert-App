import re

with open('lib/screens/create_alert_sheet.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Update build method so when in multiStepChain, options and single button are hidden (since Chain has its own bottom bar and timeout card)
old_options_marker = '''            // OPTIONS Section
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),'''

new_options_marker = '''            // OPTIONS Section (Only for single alert types)
            if (_alertType != AlertType.multiStepChain) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),'''

if old_options_marker in content and new_options_marker not in content:
    content = content.replace(old_options_marker, new_options_marker)
    # And close the if before the end of build
    old_end_build = '''            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }'''
    new_end_build = '''            const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }'''
    content = content.replace(old_end_build, new_end_build)
    print('Updated build method for multiStepChain branching')

# 2. Replace _buildLogicChainSection up to _buildPriceNodeControls
logic_chain_replacement = '''  List<Widget> _buildLogicChainSection(ThemeData theme, bool isDark) {
    return [
      // Name row card
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: _s1, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            const Text('Name', style: TextStyle(fontSize: 16, color: _t2)),
            const SizedBox(width: 14),
            Expanded(
              child: TextField(
                controller: _chainNameController,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),

      // Default stage timeout card
      GestureDetector(
        onTap: _showTimeoutPicker,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: _s1, borderRadius: BorderRadius.circular(16)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Default stage timeout', style: TextStyle(fontSize: 16, color: Colors.white)),
              Row(
                children: [
                  Text('$_defaultTimeoutMinutes min', style: AppTheme.mono(fontSize: 15, fontWeight: FontWeight.w600, color: _bl)),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 16, color: _t3),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),

      // Chain Stages
      ..._chainStages.asMap().entries.map((entry) {
        final stageIdx = entry.key;
        final stage = entry.value;
        final isLastStage = stageIdx == _chainStages.length - 1;

        return Column(
          children: [
            _buildStageCardRestyled(stageIdx, stage),
            if (!isLastStage) _buildConnectorSpine(stageIdx, stage),
          ],
        );
      }),

      const SizedBox(height: 12),

      // + Add Stage dashed button
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GestureDetector(
          onTap: _addStage,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _s3, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add, color: _bl, size: 20),
                const SizedBox(width: 6),
                const Text('Add Stage', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _bl)),
              ],
            ),
          ),
        ),
      ),

      // Bottom Buttons Row: Multi-symbol + Create Chain
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Row(
          children: [
            GestureDetector(
              onTap: _openMultiSymbolPicker,
              child: Container(
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: _s2,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: const Text('Multi-symbol', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  widget.onAlertCreated(
                    symbol: widget.symbol,
                    alertType: AlertType.multiStepChain,
                    targetPrice: _chainStages.isNotEmpty && _chainStages.first.nodes.isNotEmpty ? _chainStages.first.nodes.first.targetPrice : 0.0,
                    condition: _chainStages.isNotEmpty && _chainStages.first.nodes.isNotEmpty ? _chainStages.first.nodes.first.condition : AlertCondition.crossesAbove,
                    multiStepConfig: MultiStepConfig(stages: _chainStages),
                    timeframe: _selectedTimeframe,
                    note: _chainNameController.text.trim(),
                    ringtoneTitle: _selectedRingtoneTitle,
                    ringtoneUri: _selectedRingtoneUri,
                    drawingId: widget.drawingId,
                    targetSymbols: _selectedCurrencies.toList(),
                    triggerOnCandleClose: _triggerOnCandleClose,
                    cooldownMinutes: _cooldownMinutes,
                  );
                  Navigator.pop(context);
                },
                child: Container(
                  height: 54,
                  decoration: BoxDecoration(
                    color: _bl,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: _bl.withValues(alpha: 0.4),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Text('Create Chain', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildStageCardRestyled(int stageIdx, ChainStage stage) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _s1,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row: blue circle number, Stage Name, Delete icon
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: _bl,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${stageIdx + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  stage.name,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
              if (_chainStages.length > 1)
                GestureDetector(
                  onTap: () => _removeStage(stageIdx),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, color: Color(0xFF636366), size: 20),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Nodes in this stage
          ...stage.nodes.asMap().entries.map((entry) {
            final nodeIdx = entry.key;
            final node = entry.value;
            final isExpanded = _expandedNodeIds.contains('${stageIdx}_$nodeIdx');

            return Column(
              children: [
                if (nodeIdx > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          final currentOp = node.operatorToPrevious ?? 'AND';
                          node.operatorToPrevious = currentOp == 'AND' ? 'OR' : 'AND';
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0x33BF5AF2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          node.operatorToPrevious ?? 'AND',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFD58CF7),
                          ),
                        ),
                      ),
                    ),
                  ),
                _buildNodeTile(stageIdx, nodeIdx, stage, node, isExpanded),
              ],
            );
          }),

          // Option to add condition to stage
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => _addNodeToStage(stageIdx),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 14, color: _bl),
                    SizedBox(width: 4),
                    Text('+ Add Condition', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _bl)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeTile(int stageIdx, int nodeIdx, ChainStage stage, ChainNode node, bool isExpanded) {
    final isPrice = node.nodeType == AlertType.priceLevel;
    final isIndicator = node.nodeType == AlertType.technicalIndicator;
    final isPattern = node.nodeType == AlertType.candlestickPattern;

    final Color tileBg;
    final Widget tileIcon;
    if (isPrice) {
      tileBg = const Color(0x330A84FF);
      tileIcon = const Icon(Icons.remove, color: Color(0xFF4DA3FF), size: 16);
    } else if (isIndicator) {
      tileBg = const Color(0x33BF5AF2);
      tileIcon = const Icon(Icons.waves, color: Color(0xFFD58CF7), size: 16);
    } else {
      tileBg = const Color(0x33FF9F0A);
      tileIcon = const Icon(Icons.candlestick_chart, color: Color(0xFFFFB340), size: 16);
    }

    String displayText = '';
    if (isPrice) {
      final condStr = node.condition == AlertCondition.crossesAbove
          ? 'crosses above'
          : (node.condition == AlertCondition.crossesBelow
              ? 'crosses below'
              : (node.condition == AlertCondition.lessThanOrEqual
                  ? '≤'
                  : (node.condition == AlertCondition.greaterThanOrEqual ? '≥' : 'hits')));
      displayText = 'Price $condStr ${node.targetPrice.toStringAsFixed(widget.precision > 2 ? 4 : 2)}';
    } else if (isIndicator) {
      final period = node.indicatorConfig?.params['period'] ?? 14;
      final level = node.indicatorConfig?.params['level'] ?? 70;
      final indName = node.indicatorConfig?.indicatorType.label ?? 'RSI';
      displayText = '$indName($period) > ${level is double ? level.toStringAsFixed(0) : level}';
    } else if (isPattern) {
      final patName = node.candlestickPattern?.label ?? 'Hammer';
      displayText = '$patName · ${node.timeframe} close';
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          final key = '${stageIdx}_$nodeIdx';
          if (_expandedNodeIds.contains(key)) {
            _expandedNodeIds.remove(key);
          } else {
            _expandedNodeIds.add(key);
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _s2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: tileBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: tileIcon,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      children: [
                        if (node.isNegated)
                          const TextSpan(
                            text: 'NOT ',
                            style: TextStyle(
                              color: Color(0xFFFF453A),
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace',
                              fontSize: 14,
                            ),
                          ),
                        TextSpan(
                          text: displayText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Icon(
                  isExpanded ? Icons.keyboard_arrow_up : Icons.tune_rounded,
                  size: 16,
                  color: _t2,
                ),
              ],
            ),
            if (isExpanded) ...[
              const Divider(color: Color(0x17FFFFFF), height: 16),
              _buildInlineNodeEditor(stageIdx, nodeIdx, stage, node),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConnectorSpine(int stageIdx, ChainStage stage) {
    return Column(
      children: [
        Container(width: 2, height: 12, color: _s3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _s1,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _s2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.access_time_filled, size: 12, color: _bl),
              const SizedBox(width: 5),
              Text(
                'within ${stage.timeoutMinutes > 0 ? stage.timeoutMinutes : _defaultTimeoutMinutes}m',
                style: AppTheme.mono(fontSize: 12, color: const Color(0xFF4DA3FF), fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        Container(width: 2, height: 12, color: _s3),
      ],
    );
  }

  void _showTimeoutPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _s1,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Default Stage Timeout', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 14),
              for (final mins in [5, 15, 30, 60, 120, 240, 1440])
                ListTile(
                  title: Text(mins >= 60 ? '${mins ~/ 60} hour(s)' : '$mins minutes', style: const TextStyle(color: Colors.white)),
                  trailing: _defaultTimeoutMinutes == mins ? const Icon(Icons.check, color: _bl) : null,
                  onTap: () {
                    setState(() {
                      _defaultTimeoutMinutes = mins;
                      for (final s in _chainStages) {
                        s.timeoutMinutes = mins;
                      }
                    });
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openMultiSymbolPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _s1,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Multi-Symbol Execution', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _selectedCurrencies = Set.from(_majorSymbols);
                        });
                        setModalState(() {});
                      },
                      child: const Text('Select All', style: TextStyle(color: _bl)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _majorSymbols.map((sym) {
                    final isSel = _selectedCurrencies.contains(sym);
                    return FilterChip(
                      label: Text(sym, style: TextStyle(color: isSel ? Colors.white : _t2, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                      selected: isSel,
                      selectedColor: _bl.withValues(alpha: 0.3),
                      backgroundColor: _s2,
                      checkmarkColor: Colors.white,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedCurrencies.add(sym);
                          } else if (_selectedCurrencies.length > 1) {
                            _selectedCurrencies.remove(sym);
                          }
                        });
                        setModalState(() {});
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _bl,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Done (${_selectedCurrencies.length} selected)', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInlineNodeEditor(int stageIdx, int nodeIdx, ChainStage stage, ChainNode node) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  node.isNegated = !node.isNegated;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: node.isNegated ? const Color(0x33FF453A) : _s3,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  node.isNegated ? 'NOT active' : '+ NOT invert',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: node.isNegated ? const Color(0xFFFF453A) : _t2,
                  ),
                ),
              ),
            ),
            const Spacer(),
            _nodeTypeChip(stageIdx, nodeIdx, stage, node, AlertType.priceLevel, 'Price'),
            const SizedBox(width: 4),
            _nodeTypeChip(stageIdx, nodeIdx, stage, node, AlertType.candlestickPattern, 'Pattern'),
            const SizedBox(width: 4),
            _nodeTypeChip(stageIdx, nodeIdx, stage, node, AlertType.technicalIndicator, 'Indicator'),
            if (stage.nodes.length > 1) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _removeNodeFromStage(stageIdx, nodeIdx),
                child: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFFF453A)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        if (node.nodeType == AlertType.priceLevel)
          _buildPriceNodeControls(stageIdx, nodeIdx, stage, node, theme, true)
        else if (node.nodeType == AlertType.candlestickPattern)
          _buildPatternNodeControls(stageIdx, nodeIdx, stage, node, theme, true)
        else
          _buildIndicatorNodeControls(stageIdx, nodeIdx, stage, node, theme, true),
      ],
    );
  }

  Widget _nodeTypeChip(
    int stageIdx,
    int nodeIdx,
    ChainStage stage,
    ChainNode node,
    AlertType type,
    String label,
  ) {
    final isSelected = node.nodeType == type;
    return GestureDetector(
      onTap: () {
        setState(() {
          stage.nodes[nodeIdx] = ChainNode(
            id: node.id,
            nodeType: type,
            targetPrice: node.targetPrice > 0 ? node.targetPrice : widget.currentPrice,
            condition: node.condition,
            candlestickPattern: node.candlestickPattern ?? CandlestickPattern.bullishEngulfing,
            indicatorConfig: node.indicatorConfig ?? _buildCurrentIndicatorConfig(),
            timeframe: node.timeframe,
            isNegated: node.isNegated,
            operatorToPrevious: node.operatorToPrevious,
          );
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? _bl : _s3,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

'''

start_marker = '  List<Widget> _buildLogicChainSection'
end_marker = '  Widget _buildPriceNodeControls('

idx_start = content.find(start_marker)
idx_end = content.find(end_marker)

if idx_start == -1 or idx_end == -1:
    print('Failed to find logic chain slice markers! idx_start:', idx_start, 'idx_end:', idx_end)
else:
    new_content = content[:idx_start] + logic_chain_replacement + content[idx_end:]
    with open('lib/screens/create_alert_sheet.dart', 'w', encoding='utf-8') as f:
        f.write(new_content)
    print('Updated _buildLogicChainSection and related methods successfully!')
