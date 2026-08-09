#!/usr/bin/env bash
set -euo pipefail

verify=false
if [[ "${1:-}" == "--verify" ]]; then
  verify=true
elif [[ $# -gt 0 ]]; then
  echo "Usage: codex-local-register [--verify]" >&2
  exit 2
fi

bundle_dir="$(pwd -P)"
manifest_path="$bundle_dir/manifest.env"
certificate_path="$bundle_dir/local-llm-root.crt"
key_path="$bundle_dir/local-llm.key"

for required_path in "$manifest_path" "$certificate_path" "$key_path"; do
  if [[ ! -f "$required_path" ]]; then
    echo "This command must run from a local LLM deployment bundle. Missing: $required_path" >&2
    exit 1
  fi
done

bundle_value() {
  local name="$1"
  local value
  value="$(awk -F= -v name="$name" '$1 == name { sub(/^[^=]*=/, ""); print; exit }' "$manifest_path")"
  if [[ -z "$value" ]]; then
    echo "Bundle manifest is missing $name." >&2
    exit 1
  fi
  printf '%s' "$value"
}

assert_value() {
  local name="$1" value="$2" pattern="$3"
  if [[ ! "$value" =~ $pattern ]]; then
    echo "Bundle value $name is invalid." >&2
    exit 1
  fi
}

bundle_format="$(bundle_value BUNDLE_FORMAT)"
profile_name="$(bundle_value PROFILE_NAME)"
provider_id="$(bundle_value PROVIDER_ID)"
display_name="$(bundle_value DISPLAY_NAME)"
base_url="$(bundle_value BASE_URL)"
default_model="$(bundle_value DEFAULT_MODEL)"

[[ "$bundle_format" == "1" ]] || { echo "Unsupported local LLM bundle format: $bundle_format" >&2; exit 1; }
assert_value PROFILE_NAME "$profile_name" '^[A-Za-z0-9_-]+$'
assert_value PROVIDER_ID "$provider_id" '^[A-Za-z0-9_-]+$'
assert_value BASE_URL "$base_url" '^https://[A-Za-z0-9.-]+(:[0-9]+)?/v1$'
assert_value DEFAULT_MODEL "$default_model" '^[A-Za-z0-9._:-]+$'

api_key="$(tr -d '\r\n' < "$key_path")"
if [[ -z "$api_key" || "$api_key" =~ [[:space:]] ]]; then
  echo "local-llm.key must contain one non-empty API key with no whitespace." >&2
  exit 1
fi

codex_home="${CODEX_HOME:-$HOME/.codex}"
mkdir -p "$codex_home"
chmod 700 "$codex_home" 2>/dev/null || true
token_path="$codex_home/$profile_name.token"
token_helper_path="$codex_home/$profile_name-token.sh"
profile_path="$codex_home/$profile_name.config.toml"

umask 077
printf '%s\n' "$api_key" > "$token_path"
cat > "$token_helper_path" <<EOF
#!/usr/bin/env sh
set -eu
token_path='$token_path'
token=\$(tr -d '\\r\\n' < "\$token_path")
[ -n "\$token" ] || { echo "The local LAN token file is empty." >&2; exit 1; }
printf '%s' "\$token"
EOF
chmod 700 "$token_path" "$token_helper_path"

case "$(uname -s)" in
  Darwin)
    security add-trusted-cert -d -r trustRoot -k "$HOME/Library/Keychains/login.keychain-db" "$certificate_path"
    ;;
  Linux)
    certificate_target="/usr/local/share/ca-certificates/thanatos-local-llm.crt"
    sudo install -Dm644 "$certificate_path" "$certificate_target"
    sudo update-ca-certificates
    ;;
  *)
    echo "Unsupported Unix platform. Use the Windows registration command on Windows." >&2
    exit 1
    ;;
esac

if [[ -f "$profile_path" ]]; then
  backup_path="$profile_path.backup-$(date +%Y%m%d-%H%M%S)"
  cp "$profile_path" "$backup_path"
  echo "Backed up the existing profile to $backup_path"
fi

cat > "$profile_path" <<EOF
model = "$default_model"
model_provider = "$provider_id"

[model_providers.$provider_id]
name = "$display_name"
base_url = "$base_url"
wire_api = "responses"
request_max_retries = 1
stream_idle_timeout_ms = 120000

[model_providers.$provider_id.auth]
command = "$token_helper_path"
timeout_ms = 5000
refresh_interval_ms = 0
EOF
chmod 600 "$profile_path"

echo "Registered Codex profile '$profile_name' for $display_name."
echo "Use it with: codex --profile $profile_name"

if ! command -v codex >/dev/null 2>&1; then
  echo "Codex CLI is not installed or not on PATH. Install it, open a new terminal, then run: codex --profile $profile_name" >&2
  exit 0
fi

if [[ "$verify" == true ]]; then
  codex --profile "$profile_name" exec --skip-git-repo-check "Reply exactly: local LAN registration verified."
fi
