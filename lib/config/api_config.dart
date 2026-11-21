/// App-wide provider configuration supplied at build time.
///
/// Pass values with `--dart-define-from-file=api.env.json`. These values are
/// shared by every installation of that build. Do not put private provider
/// credentials here for a public release; compile-time defines are extractable
/// from a mobile binary. Use a server proxy for private credentials.
abstract final class ApiConfig {
  static const llmBaseUrl = String.fromEnvironment(
    'LLM_BASE_URL',
    defaultValue: 'https://openrouter.ai/api/v1',
  );
  static const llmApiKey = String.fromEnvironment('LLM_API_KEY');
  static const llmModel = String.fromEnvironment(
    'LLM_MODEL',
    defaultValue: 'nvidia/nemotron-3.5-super-vl:free',
  );
  static const realMarketBaseUrl = String.fromEnvironment(
    'REALMARKET_BASE_URL',
    defaultValue: 'https://api.realmarketapi.com',
  );
  static const realMarketApiKey = String.fromEnvironment('REALMARKET_API_KEY');
}
