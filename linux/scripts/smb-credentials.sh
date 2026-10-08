#!/usr/bin/env bash

# Materialize one remote's SMB username and password from
# config-local/smb-credentials.json into a private cifs credentials file.
# Chapters such as "ardis" and "personal" each hold one entry per remote target.
# Hades and MasterChief share the same entry.

forge_smb_credentials_json() {
  printf '%s\n' "${FORGE_ROOT}/config-local/smb-credentials.json"
}

forge_smb_materialize_credentials() {
  local chapter="$1"
  local remote="$2"
  local json_file status tmp

  [[ -n "$chapter" && -n "$remote" ]] || die "SMB credential chapter and remote are required."

  json_file="$(forge_smb_credentials_json)"
  [[ -f "$json_file" ]] || die "Missing SMB credentials: $json_file"
  require_cmd jq

  status="$(jq -r --arg chapter "$chapter" --arg remote "$remote" '
    if (.[$chapter] | type) != "object" then "missing-chapter"
    elif (.[$chapter][$remote] | type) != "object" then "missing-remote"
    elif ((.[$chapter][$remote].username // "") == "" or (.[$chapter][$remote].password // "") == "") then "empty"
    else "ok"
    end
  ' "$json_file")" || die "SMB credentials file is not valid JSON: $json_file"

  case "$status" in
    ok) ;;
    missing-chapter)
      die "SMB credentials have no '${chapter}' chapter in $json_file."
      ;;
    missing-remote)
      die "SMB credentials chapter '${chapter}' has no entry for remote '${remote}'."
      ;;
    empty)
      die "Fill username and password for ${chapter}.${remote} in $json_file."
      ;;
    *)
      die "Could not read SMB credentials for ${chapter}.${remote}."
      ;;
  esac

  tmp="$(mktemp "${TMPDIR:-/tmp}/forge-smb-credentials.XXXXXX")"
  chmod 600 "$tmp"
  if ! jq -r --arg chapter "$chapter" --arg remote "$remote" '
    .[$chapter][$remote]
    | "username=\(.username)\npassword=\(.password)"
  ' "$json_file" > "$tmp"; then
    rm -f -- "$tmp"
    die "Could not write SMB credentials for ${chapter}.${remote}."
  fi
  printf '%s\n' "$tmp"
}
