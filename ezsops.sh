#!/bin/bash

set -e

# Initialize verbose flag
verbose=0

# Parse command-line arguments
for arg in "$@"; do
  if [[ $arg == "-v" || $arg == "--verbose" ]]; then
    echo "Verbose mode enabled"
    verbose=1
    break # Optional: remove if you want to check for other flags
  fi
done

# Define verbose logging function
log_verbose() {
  if [[ $verbose -eq 1 ]]; then
    echo "$@"
  fi
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: Required command '$1' is not installed or not in PATH."
    return 1
  fi
}

ezsops_decrypt() {
  if [ -z "$1" ]; then
    echo "Usage: ezsops decrypt <path/to/sops.filename.yml>"
    return 1
  fi

  require_command "sops" || return 1

  encrypted_file="$1"

  if [ ! -f "${encrypted_file}" ]; then
    echo "Error: Encrypted file '${encrypted_file}' not found."
    return 1
  fi

  decrypted_file="${encrypted_file%.*}.yml"
  decrypted_file="${decrypted_file/sops./}"

  decrypted_tmp_file="$(mktemp "${decrypted_file}.tmp.XXXXXX")"

  if sops -d "${encrypted_file}" > "${decrypted_tmp_file}"; then
    mv "${decrypted_tmp_file}" "${decrypted_file}"
  else
    rm -f "${decrypted_tmp_file}"
    return 1
  fi

  echo "Decrypted '${encrypted_file}' to '${decrypted_file}'"
}

ezsops_encrypt() {
  if [ -z "$1" ]; then
    echo "Usage: ezsops encrypt <path/to/filename.yml>"
    return 1
  fi

  require_command "sops" || return 1
  require_command "yq" || return 1

  decrypted_file="$1"
  encrypted_dir="${decrypted_file%/*}"
  if [ "${encrypted_dir}" = "${decrypted_file}" ]; then
    encrypted_file="sops.${decrypted_file##*/}"
  else
    encrypted_file="${encrypted_dir}/sops.${decrypted_file##*/}"
  fi

  log_verbose "Encrypting file: ${decrypted_file}"
  log_verbose "Destination file: ${encrypted_file}"

  if [ ! -f "${decrypted_file}" ]; then
    echo "Error: Decrypted file '${decrypted_file}' not found."
    return 1
  fi

  # Regex pattern to match
  regex="^(data|stringData|secrets)$"

  # Flag to indicate if a match is found
  match_found=0

  # Extract top-level keys using yq and check against regex
  # This is done with process substitution to avoid creating a subshell, allowing us to correctly set `match_found`
  while read -r key; do
    if [[ $key =~ $regex ]]; then
      log_verbose "Found a top-level key matching the encryption pattern: $key"
      match_found=1
      break
    fi
  done < <(yq e 'keys | .[]' "$decrypted_file")

  # Check if a match was found
  if [[ $match_found -eq 0 ]]; then
    echo "Error: No top-level key found matching the encyption pattern: ${regex}"
    echo "This could mean that your file will not be encrypted correctly. Aborting now."
    exit 1
  fi

  kms_file="$HOME/.sops_kms_arns"

  log_verbose "Looking up KMS ARN file: ${kms_file}"

  if [ ! -f "${kms_file}" ]; then
    log_verbose "KMS ARN file not found. Creating a new one."
    touch "${kms_file}"
  fi

  use_existing_key=""
  while [[ "$use_existing_key" != "y" && "$use_existing_key" != "n" ]]; do
    echo -n "Do you want to use a pre-existing KMS key? (y/n): "
    read -r use_existing_key
  done

  if [ "$use_existing_key" = "y" ]; then
    options=()
    while IFS= read -r option; do
      options+=("${option}")
    done < <(awk -F'\t' '{print $1 "\t" $2 "\t" $3}' "${kms_file}")
    if [ ${#options[@]} -eq 0 ]; then
      echo "Error: No pre-existing KMS keys were found in '${kms_file}'."
      return 1
    fi

    echo "Select a KMS ARN:"
    printf "%-4s | %-12s | %-75s | %-20s\n" "No." "Date" "ARN" "Label"
    echo "---------------------------------------------------------------------------------------------------------------"
    index=1
    for option in "${options[@]}"; do
      IFS=$'\t' read -r date arn label <<< "$option"
      if [ -z "${date}" ] || [ -z "${arn}" ] || [ -z "${label}" ]; then
        echo "Error: Invalid KMS entry found in '${kms_file}'."
        return 1
      fi
      printf "%-4d | %-12s | %-75s | %-20s\n" "${index}" "${date}" "${arn}" "${label}"
      index=$((index + 1))
    done
    echo -n "Enter the number of the KMS ARN: "
    read -r choice
    if ! [[ "${choice}" =~ ^[0-9]+$ ]]; then
      echo "Error: Invalid selection '${choice}'."
      return 1
    fi
    if [ "${choice}" -lt 1 ] || [ "${choice}" -gt ${#options[@]} ]; then
      echo "Error: Selection '${choice}' is out of range."
      return 1
    fi
    IFS=$'\t' read -r _ kms_arn _ <<< "${options[((choice - 1))]}"
  else
    echo -n "Enter new KMS ARN: "
    read -r new_kms_arn
    if [ -z "${new_kms_arn}" ]; then
      echo "Invalid KMS ARN. Aborting."
      return 1
    fi
    echo -n "Enter a label for the new KMS ARN: "
    read -r new_label
    if [ -z "${new_label}" ]; then
      echo "Invalid label. Aborting."
      return 1
    fi
    current_date=$(date "+%Y-%m-%d")
    echo -e "${current_date}\t${new_kms_arn}\t${new_label}" >> "${kms_file}"
    kms_arn="${new_kms_arn}"
  fi

  if [ -z "${kms_arn}" ]; then
    echo "Error: No KMS ARN was selected."
    return 1
  fi

  log_verbose "Using KMS ARN: ${kms_arn}"

  encrypted_tmp_file="$(mktemp "${encrypted_file}.tmp.XXXXXX")"

  if sops -e --kms "${kms_arn}" --encrypted-regex "${regex}" "${decrypted_file}" > "${encrypted_tmp_file}"; then
    mv "${encrypted_tmp_file}" "${encrypted_file}"
  else
    rm -f "${encrypted_tmp_file}"
    return 1
  fi

  echo "Encrypted '${decrypted_file}' to '${encrypted_file}' using KMS ARN '${kms_arn}'"
}

ezsops () {
if [ "$1" = "encrypt" ]; then
  ezsops_encrypt "${@:2}"
elif [ "$1" = "decrypt" ]; then
  ezsops_decrypt "${@:2}"
else
  echo "Usage: ezsops <encrypt|decrypt> [args]"
  return 1
fi
}

if [[ ${BASH_SOURCE[0]} != "$0" ]]; then
  export -f ezsops
else
  ezsops "${@}"
  exit $?
fi
