// Renders the provider config for one agent from LLM_* environment variables.
// Usage: node llm-config.js <pi|codex>
// Env: LLM_BASE_URL (required), LLM_API_KEY (required), LLM_MODEL (required),
//      LLM_MODELS (optional, comma-separated extra model ids; Pi only).
const fs = require('fs');
const os = require('os');
const path = require('path');

function fail(message) {
  process.stderr.write(`llm-config: ${message}\n`);
  process.exit(1);
}

function splitList(value) {
  return (value || '').split(',').map((s) => s.trim()).filter(Boolean);
}

function writeFile(file, content) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content);
}

function piModels(env) {
  const ids = [...new Set([env.LLM_MODEL, ...splitList(env.LLM_MODELS)])];
  // Pi expands $NAME in apiKey at request time, so the key never lands on disk.
  const config = {
    providers: {
      llm: {
        baseUrl: env.LLM_BASE_URL,
        api: 'openai-completions',
        apiKey: '$LLM_API_KEY',
        models: ids.map((id) => ({ id })),
      },
    },
  };
  writeFile(path.join(os.homedir(), '.pi', 'agent', 'models.json'), `${JSON.stringify(config, null, 2)}\n`);
}

function codexConfig(env) {
  // Codex needs the Responses API (wire_api = "responses") from the endpoint.
  const toml = `model = ${JSON.stringify(env.LLM_MODEL)}
model_provider = "llm"
check_for_update_on_startup = false

[otel]
exporter = "none"
trace_exporter = "none"
metrics_exporter = "none"

[model_providers.llm]
name = "LLM endpoint"
base_url = ${JSON.stringify(env.LLM_BASE_URL)}
env_key = "LLM_API_KEY"
wire_api = "responses"
requires_openai_auth = false
`;
  writeFile(path.join(os.homedir(), '.codex', 'config.toml'), toml);
}

const tool = process.argv[2];
const env = process.env;
if (!env.LLM_BASE_URL) fail('LLM_BASE_URL is required (OpenAI-compatible base URL, e.g. https://host/v1)');
if (!env.LLM_API_KEY) fail('LLM_API_KEY is required');
if (!env.LLM_MODEL) fail('LLM_MODEL is required (default model id)');

if (tool === 'pi') piModels(env);
else if (tool === 'codex') codexConfig(env);
else fail(`unknown tool "${tool}" (expected pi or codex)`);
