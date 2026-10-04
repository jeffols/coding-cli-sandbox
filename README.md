# pi-sandbox

Run the [Pi](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) and [Codex](https://www.npmjs.com/package/@openai/codex) coding agents in Docker containers, pointed at any OpenAI-compatible LLM endpoint.

The containers mount one workspace directory, so the agents can read and edit only what you give them. Provider configuration is generated at container start from environment variables, so no keys or endpoints are baked into the images.

## Requirements

- Docker with BuildKit (Docker Desktop, or Docker Engine 23+)
- `make`
- An OpenAI-compatible endpoint: OpenAI itself, a LiteLLM gateway, or similar

## Quick start

```sh
export LLM_BASE_URL=https://api.openai.com/v1   # or http://localhost:4000/v1 for LiteLLM
export LLM_API_KEY=...                          # your key for that endpoint
export LLM_MODEL=gpt-4o-mini                    # a model the endpoint serves

make run                                        # Pi, interactive
make run-codex CODEX_MODEL=gpt-5                # Codex, interactive; needs a Responses API model
```

Run `make help` for every target and variable.

## Configuration

Set these in your shell (for example in `~/.zshrc`):

| Variable | Meaning |
|---|---|
| `LLM_BASE_URL` | Base URL including `/v1`. Loopback hosts (`localhost`, `127.0.0.1`) are rewritten to `host.docker.internal` for the container |
| `LLM_API_KEY` | Bearer key for the endpoint. Passed into the container as an environment variable; never written to an image |
| `LLM_MODEL` | Default model id. Pi uses it for `--model`; Codex uses it as its configured model |
| `LLM_MODELS` | Optional comma-separated extra model ids to offer in Pi |
| `MODEL`, `CODEX_MODEL` | Override the model for one run |
| `WORKSPACE` | Directory mounted at `/workspace`. Defaults to `./workspace/` |

Each container writes its own provider config at start, using `container/llm-config.js`: Pi's `models.json`, and Codex's `config.toml`.

### Model requirements

- **Pi** uses chat completions (`openai-completions`).
- **Codex** uses the Responses API (`wire_api = "responses"`), so its model must be served on `/v1/responses`. Some endpoints offer only chat completions. Check a model before relying on it:

  ```sh
  curl -s "$LLM_BASE_URL/responses" -H "Authorization: Bearer $LLM_API_KEY" \
    -H 'content-type: application/json' -d '{"model":"<id>","input":"hi"}'
  ```

## Workspace

Both interactive targets mount `./workspace/` by default, not the project root. Point `WORKSPACE` at any other directory:

```sh
make run WORKSPACE="$HOME/src/my-project"
```

An explicit workspace that does not exist is rejected rather than created.

Pi's configuration persists in `~/.pi/agent`. Codex's persists in `~/.codex/pi-sandbox`. Both are host directories mounted into the container.

## Corporate proxy and custom CA (optional)

Most machines need none of this.

- `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY` from your environment are passed to the build and to the container. Add your network's no-proxy hosts to `NO_PROXY`.
- `CA_BUNDLE` is a path to a PEM file of extra CA roots, for networks that intercept TLS. It is mounted as a build secret and at `/run/secrets/ca_bundle` in the run container, with `NODE_EXTRA_CA_CERTS` pointing there. The CA is never baked into an image. `make` fails if `CA_BUNDLE` names a missing file.

  ```sh
  export CA_BUNDLE="$HOME/certs/corp-root.pem"
  make run
  ```

## Security notes

- Only the selected workspace, the agent's state directory, and the optional `CA_BUNDLE` are mounted. Do not mount the Docker socket or sensitive host directories.
- Anything in the workspace is writable from inside the container. Use a copy or a clean Git clone if you want to keep the original untouched (see below).
- Codex's own `bubblewrap` sandbox cannot create user namespaces in many Docker runtimes, so `run-codex` starts Codex with `--sandbox danger-full-access`. Inside the container, the Docker boundary is the isolation.
- Pi's automatic reporting and catalog fetches are disabled in its image. Codex's telemetry exporters and update check are disabled in its generated config.
- The LLM endpoint receives every model call the agents make, along with the code they read. Choose an endpoint you trust with that content.

## Dueling agents

To compare the agents on the same task, start from a clean Git repository. Each agent gets its own clone at the same commit:

```sh
make duel-setup REPO=/absolute/path/to/repo
make run WORKSPACE="$PWD/duel/pi" MODEL=<model-id>
make run-codex WORKSPACE="$PWD/duel/codex"
```

Start the two runs in separate terminals and paste the same prompt into each. Then compare `git -C duel/pi status --short` with `git -C duel/codex status --short`, their diffs, and their test results. `duel-setup` refuses a dirty source repository and existing clone paths. It never modifies the source repository, and it does not delete the clones afterwards.

## Image versions

```sh
make build PI_VERSION=1.0.0
make build-codex CODEX_VERSION=0.160.0
```

`make run` and `make run-codex` rebuild their images first, so changes to the Dockerfiles or `container/` take effect automatically. Docker's layer cache keeps this fast: the Python and uv layer is reused, and Codex has its own layer.

## Third-party software

The images install these packages, which keep their own licenses:

- [Pi coding agent](https://www.npmjs.com/package/@earendil-works/pi-coding-agent), installed from npm
- [Codex CLI](https://www.npmjs.com/package/@openai/codex), installed from npm
- [uv](https://github.com/astral-sh/uv) and Python 3.12, installed at build time
- Debian packages: bash, curl, git, ripgrep, fd-find, ca-certificates

This project is not affiliated with or endorsed by their authors.

## License

MIT. See [LICENSE](LICENSE).
