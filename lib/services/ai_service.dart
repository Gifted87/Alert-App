import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/ai_models.dart';
import 'app_remote_config.dart';
import 'settings_provider.dart';

class AiService {
  final http.Client _client;
  LlmConfig config;

  AiService({http.Client? client, LlmConfig? config})
    : _client = client ?? http.Client(),
      config =
          config ??
          LlmConfig(
            baseUrl: LlmConfig.defaultSettings.baseUrl,
            apiKey: LlmConfig.defaultSettings.apiKey,
            modelName: AppRemoteConfig.instance.llmModel,
          );

  /// Tests the OpenAI-compatible endpoint with a minimal completion request
  Future<bool> testConnection() async {
    try {
      final res = await complete(
        systemPrompt: 'You are a health-check responder. Reply with standard JSON: {"status": "ok"}',
        userPrompt: 'Ping',
        temperature: 0.1,
      );
      return res.isNotEmpty;
    } catch (e) {
      debugPrint('AiService testConnection failed: $e');
      return false;
    }
  }

  /// Performs an OpenAI-compatible /v1/chat/completions call without function calling.
  Future<String> complete({
    required String systemPrompt,
    required String userPrompt,
    double temperature = 0.3,
    int maxTokens = 8000,
  }) async {
    final cleanBase = config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final endpoint = cleanBase.endsWith('/v1')
        ? '$cleanBase/chat/completions'
        : '$cleanBase/v1/chat/completions';

    final uri = Uri.parse(endpoint);
    final headers = {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
    };
    if (config.apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${config.apiKey.trim()}';
    }

    final settings = SettingsProvider();
    var effectiveSystemPrompt = systemPrompt;
    if (settings.aiTraderDirective.trim().isNotEmpty) {
      effectiveSystemPrompt +=
          '\n\n=== GLOBAL TRADER DIRECTIVE ===\n${settings.aiTraderDirective.trim()}';
    }
    final effTemp = settings.llmTemperature;
    final effTokens = AppRemoteConfig.instance.llmMaxOutputTokens;

    final body = jsonEncode({
      'model': AppRemoteConfig.instance.llmModel,
      'messages': [
        {'role': 'system', 'content': effectiveSystemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      'temperature': effTemp,
      'max_tokens': effTokens,
      // The configured OpenRouter model is a reasoning model. Leaving its
      // reasoning budget at the provider default can spend most of a request
      // thinking before it starts returning the structured signal. Keep the
      // model's reasoning focused so a multi-stage analysis can complete.
      if (uri.host == 'openrouter.ai' || uri.host.endsWith('.openrouter.ai'))
        'reasoning_effort': 'low',
    });

    final response = await _client
        .post(uri, headers: headers, body: body)
        .timeout(Duration(seconds: AppRemoteConfig.instance.llmTimeoutSeconds));

    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        final choices = decoded['choices'] as List<dynamic>?;
        if (choices != null && choices.isNotEmpty) {
          final firstChoice = choices[0] as Map<String, dynamic>;
          final message = firstChoice['message'] as Map<String, dynamic>?;
          var content = message?['content']?.toString() ?? '';
          if (content.isEmpty && message?['reasoning_content'] != null) {
            content = message!['reasoning_content'].toString();
          }
          return content;
        }
      }
      throw Exception('Malformed chat completion response: ${response.body}');
    } else {
      throw Exception('LLM HTTP ${response.statusCode}: ${response.body}');
    }
  }

  /// Sends a structured prompt and parses the returned JSON into an AgentSignal
  Future<AgentSignal> completeStructuredSignal({
    required String agentName,
    required String systemPrompt,
    required String userPrompt,
    double currentPrice = 0.0,
    double temperature = 0.3,
    String? symbol,
  }) async {
    final structuredInstruction =
        '''
$systemPrompt

CRITICAL MANDATORY INSTRUCTIONS:
You MUST respond with a single, valid JSON object inside a ```json ``` code block.
DO NOT use markdown formatting outside the JSON block.
DO NOT use function/tool calling.
Your JSON object MUST contain exactly these fields:
{
  "direction": "buy" | "sell" | "wait",
  "analysis": "detailed text analysis of current market structure, imbalances, and order flow",
  "theory": "text explanation of the theory and prediction rationale",
  "entry_price": <a single exact numeric price, e.g. 1.15450, NOT a range>,
  "stop_loss": <a single exact numeric price for invalidation, e.g. 1.15120, NOT a range>,
  "take_profit": <a single exact numeric target price, e.g. 1.16100, NOT a range>,
  "confidence": <integer from 1 to 10 rating your conviction>
}
NOTE: If there is a price range or buffer you advise, explain it inside "analysis" and "theory". "entry_price", "stop_loss", and "take_profit" MUST be single clean numbers. If direction is "wait", set entry_price, stop_loss, and take_profit to $currentPrice.
''';

    final rawContent = await complete(
      systemPrompt: structuredInstruction,
      userPrompt: userPrompt,
      temperature: temperature,
    );

    return extractSignalFromJson(
      rawContent,
      agentName: agentName,
      fallbackPrice: currentPrice,
      symbol: symbol,
    );
  }

  /// Extracts the AgentSignal from a completion string containing JSON
  static AgentSignal extractSignalFromJson(
    String content, {
    required String agentName,
    double fallbackPrice = 0.0,
    String? symbol,
  }) {
    Map<String, dynamic>? parsedJson;

    // 1. Try markdown code block regex ```json ... ```
    final codeBlockRegex = RegExp(
      r'```(?:json)?\s*([\s\S]*?)\s*```',
      caseSensitive: false,
    );
    final match = codeBlockRegex.firstMatch(content);
    if (match != null) {
      try {
        final block = match.group(1)!.trim();
        parsedJson = jsonDecode(block) as Map<String, dynamic>;
      } catch (_) {}
    }

    // 2. Try raw substring between first '{' and last '}'
    if (parsedJson == null) {
      final start = content.indexOf('{');
      final end = content.lastIndexOf('}');
      if (start != -1 && end != -1 && end > start) {
        try {
          final candidate = content.substring(start, end + 1);
          parsedJson = jsonDecode(candidate) as Map<String, dynamic>;
        } catch (_) {}
      }
    }

    // 3. Fallback if JSON parsing totally fails: build safe AgentSignal from text
    if (parsedJson == null) {
      debugPrint(
        'AiService: Could not parse pure JSON from agent output. Using text heuristic fallback.',
      );
      final lower = content.toLowerCase();
      final dir = lower.contains('buy') || lower.contains('bullish')
          ? SignalDirection.buy
          : (lower.contains('sell') || lower.contains('bearish')
                ? SignalDirection.sell
                : SignalDirection.wait);

      return AgentSignal(
        direction: dir,
        analysis: content,
        theory: 'Parsed from free-form agent analysis.',
        entryPrice: fallbackPrice,
        stopLoss: dir == SignalDirection.buy
            ? fallbackPrice * 0.995
            : fallbackPrice * 1.005,
        takeProfit: dir == SignalDirection.buy
            ? fallbackPrice * 1.010
            : fallbackPrice * 0.990,
        confidence: 5,
        agentName: agentName,
        timestamp: DateTime.now(),
        rawJson: content,
        symbol: symbol,
      );
    }

    final sig = AgentSignal.fromJson(parsedJson, defaultAgentName: agentName);
    return symbol != null && (sig.symbol == null || sig.symbol!.isEmpty)
        ? sig.copyWith(symbol: symbol)
        : sig;
  }
}
