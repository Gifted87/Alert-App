import re

with open('lib/screens/create_alert_sheet.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add fields in _CreateAlertSheetState
if '_chainNameController' not in content:
    content = content.replace(
        '  bool _showAdvancedOptions = false;',
        '''  bool _showAdvancedOptions = false;
  final TextEditingController _chainNameController = TextEditingController(text: 'Breakout → Pullback → Hammer');
  int _defaultTimeoutMinutes = 30;
  final Set<String> _expandedNodeIds = {};'''
    )

# 2. Update dispose to dispose _chainNameController
if '_chainNameController.dispose();' not in content:
    content = content.replace(
        '    _noteController.dispose();',
        '    _noteController.dispose();\n    _chainNameController.dispose();'
    )

# 3. Update default _chainStages in initState to match the exact design in the image
old_chain_init = '''    } else {
      _chainStages = [
        ChainStage(
          id: 'stage_1',
          name: 'Price Level Touch',
          logicOperator: 'AND',
          nodes: [
            ChainNode(
              id: 'node_1',
              nodeType: AlertType.priceLevel,
              targetPrice: _targetPrice,
              condition: _condition,
            ),
          ],
        ),
        ChainStage(
          id: 'stage_2',
          name: 'Momentum / Indicator Confluence',
          logicOperator: 'AND',
          nodes: [
            ChainNode(
              id: 'node_2',
              nodeType: AlertType.technicalIndicator,
              indicatorConfig: IndicatorAlertConfig(
                indicatorType: AlertIndicatorType.rsi,
                condition: 'crossesBelow',
                params: {
                  'period': 14,
                  'level': 30.0,
                  'source': 'Close',
                  'smoothingType': 'RMA',
                  'overbought': 70.0,
                  'oversold': 30.0,
                },
              ),
              timeframe: '15m',
            ),
          ],
        ),
      ];
    }'''

new_chain_init = '''    } else {
      _chainStages = [
        ChainStage(
          id: 'stage_1',
          name: 'Breakout',
          timeoutMinutes: 30,
          logicOperator: 'AND',
          nodes: [
            ChainNode(
              id: 'node_1',
              nodeType: AlertType.priceLevel,
              targetPrice: 1.0925,
              condition: AlertCondition.crossesAbove,
            ),
          ],
        ),
        ChainStage(
          id: 'stage_2',
          name: 'Pullback to support',
          timeoutMinutes: 30,
          logicOperator: 'AND',
          nodes: [
            ChainNode(
              id: 'node_2_1',
              nodeType: AlertType.priceLevel,
              targetPrice: 1.0890,
              condition: AlertCondition.crossesBelow,
              operatorToPrevious: 'AND',
            ),
            ChainNode(
              id: 'node_2_2',
              nodeType: AlertType.technicalIndicator,
              isNegated: true,
              indicatorConfig: IndicatorAlertConfig(
                indicatorType: AlertIndicatorType.rsi,
                condition: 'crossesAboveLevel',
                params: {
                  'period': 14,
                  'level': 70.0,
                  'source': 'Close',
                  'smoothingType': 'RMA',
                },
              ),
              timeframe: '15m',
              operatorToPrevious: 'AND',
            ),
          ],
        ),
        ChainStage(
          id: 'stage_3',
          name: 'Confirmation',
          timeoutMinutes: 30,
          logicOperator: 'AND',
          nodes: [
            ChainNode(
              id: 'node_3_1',
              nodeType: AlertType.candlestickPattern,
              candlestickPattern: CandlestickPattern.hammer,
              timeframe: '15m',
              operatorToPrevious: 'AND',
            ),
          ],
        ),
      ];
    }'''

if old_chain_init in content:
    content = content.replace(old_chain_init, new_chain_init)
    print('Updated initState _chainStages to match image')
else:
    print('Warning: old_chain_init pattern not found directly, checking...')

with open('lib/screens/create_alert_sheet.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print('Step 1 finished')
