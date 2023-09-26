#!/bin/bash
# Gets a protonmail code from https://maildrop.cc

# Debug:
#set -x
set -Eeuo pipefail

# Output file
GENERATED_ACCOUNTS="$(dirname "$0")/generated_protonmail.csv"

# Add common functions
COMMON_FUNCTIONS="$(dirname "$0")/common_shell_functions/common_bash_functions.sh"
if [ -x "$COMMON_FUNCTIONS" ]; then
  # shellcheck source=/dev/null
  source "$COMMON_FUNCTIONS"
elif [ -f "$COMMON_FUNCTIONS" ]; then
  echo "Error, make sure common includes are executable, you may need to run:
    chmod +x $COMMON_FUNCTIONS"
  exit
else
  echo "Error, unable to find common shell includes: $COMMON_FUNCTIONS
  You may need to enable the submodule with:
    git submodule init
    git submodule update"
  exit 1
fi

# Add wordlist
WORDLIST="$(dirname "$0")/english-words/words_alpha.txt"
if [ ! -f "$WORDLIST" ]; then
  echo "Error, unable to find wordlist file withing get_random_word_number()
  You may need to enable the submodule with:
    git submodule init
    git submodule update"
  exit 1
fi

# Check script dependencies
check_installed "curl" "jq" "xclip"

# Choose a random word or number and return it
get_random_word_number() {
  # Check for random wordlist
  if [ "$(random_number "0" "1")" -eq 0 ]; then
    random_number "0" "999"
  else
    local line
    line=$(random_number "1" "$(wc -l < "$WORDLIST")")
    sed -n "${line}p" "$WORDLIST" | tr -dc "[:alpha:]"
  fi
}

# Choose a random word separator and return it
get_random_word_seperator() {
  local rand
  rand=$(random_number "0" "3")
  # 0 defaults to no seperator, otherwise:
  if [ "$rand" -eq 1 ]; then
    echo "-"
  elif [ "$rand" -eq 2 ]; then
    echo "_"
  elif [ "$rand" -eq 3 ]; then
    echo "."
  fi
}

# Generate a complete random username and return
get_random_username() {
  local username
  username=$(get_random_word_number)
  while [ "${#username}" -lt 10 ]; do
    username="${username}$(get_random_word_seperator)$(get_random_word_number)"
  done
  echo "$username"
}

# Generate a shortened random username and return
get_short_username() {
  echo "$(get_random_word_number)$(get_random_word_number)"
}

# Generate a random password
get_random_password() {
  local pass
  pass=$(get_random_word_number)
  while [ "${#pass}" -lt 32 ]; do
    pass="${pass}$(get_random_word_seperator)$(get_random_word_number)"
  done
  echo "$pass"
}

# Choose a random protonmail domain and return it
get_random_proton_domain() {
  if [ "$(random_number "0" "1")" -eq 0 ]; then
    echo "protonmail.com"
  else
    echo "proton.me"
  fi
}

# Create a fresh protonmail email address and return it
get_proton_address() {
  echo "$(get_random_username)@$(get_random_proton_domain)"
}

# Curl POST request function for maildrop.cc, pass data payload as arg $1
get_post_maildrop() {
  if [ -z "$1" ]; then
    echo "Error, no data payload string passed to get_post_maildrop()"
    exit 1
  fi
  # Curl vars
  local header="content-type: application/json"
  local url="https://api.maildrop.cc/graphql"
  # Get output
  curl -s -S -X POST -H "$header" -d "$1" "$url" | jq .
}

# Get the maildrop mailbox alias for a inbox passed as arg $1
get_maildrop_alias() {
  if [ -z "$1" ]; then
    echo "Error, no inbox name passed to get_maildrop_alias()"
    exit 1
  fi
  # Generate data json
  local alias
  # Get alias from remote
  alias=$(get_post_maildrop "{\"query\":\"query Example { altinbox(mailbox:\\\"${1}\\\") }\"}")
  # Trim alias out of JSON
  alias=$(echo "$alias" | grep -m 1 -F "altinbox" | cut -d":" -f2 | cut -d"\"" -f2)
  # Guard against curl errors and return
  if [ -z "$alias" ]; then
    echo "Error, empty curl result in get_maildrop_alias()"
    exit 1
  else
    echo "$alias"
  fi
}

# Get an email-ready random address for a inbox name passed as arg $1
get_maildrop_address() {
  if [ -z "$1" ]; then
    echo "Error, no inbox name passed to get_maildrop_address()"
    exit 1
  fi
  # Generate data json
  echo "$(get_maildrop_alias "$1")@maildrop.cc"
}

# Get maildrop.cc mailbox message listing for a mailbox passed as arg $1
get_maildrop_mailbox_listing() {
  if [ -z "$1" ]; then
    echo "Error, no mailbox name passed to get_maildrop_mailbox_listing()"
    exit 1
  fi
  # Get mailbox listing
  get_post_maildrop "{\"query\":\"query Example { inbox(mailbox:\\\"${1}\\\") { id headerfrom subject date } }\"}"
}

# Get maildrop.cc specific email from a mailbox (arg $1) and id (arg $2)
get_maildrop_specific_message() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error, no mailbox name or message id passed to get_maildrop_specific_message()"
    exit 1
  fi
  # Get specific message
  get_post_maildrop "{\"query\":\"query Example { message(mailbox:\\\"${1}\\\", id:\\\"${2}\\\") { id data html } }\"}" | jq -r ".data.message.html"
}

# Get proton verification code from maildrop.cc mailbox (arg $1) and id (arg $2)
get_maildrop_proton_code() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error, no mailbox name or message id passed to get_maildrop_proton_code()"
    exit 1
  fi
  # Get the raw email HTML
  local raw
  raw=$(get_maildrop_specific_message "$1" "$2")
  echo "$raw" | grep -F "</code>" | cut -d"/" -f1 | rev | cut -d">" -f1 | cut -d"<" -f2 | rev
}

# Delete a message on maildrop.cc using the mailbox (arg $1) and id (arg $2)
delete_maildrop_message() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error, no mailbox name or message id passed to delete_maildrop_message()"
    exit 1
  fi
  local status
  status=$(get_post_maildrop "{\"query\":\"mutation Example { delete(mailbox:\\\"${1}\\\", id:\\\"${2}\\\") }\"}")
  if echo "$status" | grep -F "\"delete\"" | grep -qF "true"; then
    echo "Deleted message from inbox: $1"
  else
    echo "Error, failed to delete message $2 from inbox: $1"
  fi
}

# Prompt user action and wait for any key input, pass message as arg $1
prompt_user_wait() {
  if [ -z "$1" ]; then
    echo "Error, no prompt passed to prompt_user_wait()"
    exit 1
  fi
  read -r -p "
...............................................................................
$1
Press any key to continue: "
}

# Prompt user action, copy to clipboard, and wait for any key input,
# pass message as arg $1 and string to copy as arg $2
prompt_copy_wait() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error, no prompt or copy string passed to prompt_copy_wait()"
    exit 1
  fi
  echo "$2" | xclip -sel c
  prompt_user_wait "$1
Copied to clipboard: $2"
}

# Function to create a new protonmail account, verify, secure, and output it to a csv
create_new_proton_mail() {
  # Generate account details
  local proton_email
  local proton_pword
  local burner_inbox
  local burner_email
  proton_email=$(get_proton_address)
  proton_pword=$(get_random_password)
  burner_inbox=$(get_short_username)
  burner_email=$(get_maildrop_address "$burner_inbox")

  # Prep other vars
  local mail_list
  local timeout
  local verify_code
  local verify_id=""

  # Prompt user to go to site
  prompt_copy_wait "Please go to the protonmail website and 'Create free account'" \
    "https://account.proton.me/mail/signup?plan=free&billing=12&minimumCycle=12&currency=USD&ref=prctbl"
  # Prompt user to enter username
  prompt_copy_wait "Please enter the following username and select the domain: @$(echo "$proton_email" | \
    cut -d"@" -f2)" "$(echo "$proton_email" | cut -d"@" -f1)"
  # Prompt user to enter password
  prompt_copy_wait "Please enter the following password and select 'Create acount'" \
    "$proton_pword"
  # Prompt user to verify email
  prompt_copy_wait "Please enter this verification email and select 'Get verification code'" \
    "$burner_email"

  # Get verification code and set verification timeout to 90 seconds
  timeout=$(( $(date +%s) + 90 ))
  echo "
Waiting for verification code, 90 second timeout..."
  # Busy wait
  while [ "$(date +%s)" -lt "$timeout" ] && [ -z "$verify_id" ]; do
    mail_list=$(get_maildrop_mailbox_listing "$burner_inbox")
    if echo "$mail_list" | grep -qF "Proton Verification Code"; then
      verify_id=$(echo "$mail_list" | grep -B 2 -F "Proton Verification Code" | \
        grep -F "\"id\":" | cut -d":" -f2 | cut -d"\"" -f2)
    else
      sleep 3
    fi
  done

  # Check for timeout errors
  if [ -z "$verify_id" ]; then
    echo "Error, timeout while trying to get a verification code
    From mailbox: $burner_inbox@maildrop.cc ($burner_email)"
    exit 1
  fi

  # Get verification code
  echo "Getting verification code from mailbox:message_id (${burner_inbox}:${verify_id})"
  verify_code=$(get_maildrop_proton_code "$burner_inbox" "$verify_id")
  # Check for verification code errors
  if [ -z "$verify_code" ]; then
    echo "Error getting a Proton verification code for $proton_email
    From mailbox: $burner_inbox@maildrop.cc ($burner_email)"
    exit 1
  fi

  # Prompt user to enter code
  prompt_copy_wait "Please enter the following verification code and select 'Verify'" \
    "$verify_code"

  # Delete message
  echo
  delete_maildrop_message "$burner_inbox" "$verify_id"

  # Save to csv
  if [ ! -s "$GENERATED_ACCOUNTS" ]; then
    echo "#email,#password" >> "$GENERATED_ACCOUNTS"
  fi
  echo "$proton_email,$proton_pword" >> "$GENERATED_ACCOUNTS"
  echo "$proton_email has been added to the CSV file:
  $GENERATED_ACCOUNTS"

  # Prompt user to set up account security
  prompt_user_wait "Please verify your display name and click 'Next'"
  prompt_user_wait "De-select 'Recovery email address' and select 'Maybe later' -> 'Confirm'"
  prompt_user_wait "Select 'Skip' -> 'Next' -> 'Next' -> 'Get started'"
  prompt_user_wait "Select the settings gear icon in the top-right corner -> 'All settings'"
  prompt_user_wait "De-select all email subsciptions at the bottom of the 'Dashboard' landing page"
  prompt_user_wait "Select 'Security and privacy' on the left side and DISABLE 'Enable authentication logs'"
  prompt_user_wait "Disable the 'Collect usage diagnostics' and 'Send crash reports' switches"
  echo "
Done!"
}

# Run script
create_new_proton_mail

# TODO: Guide user through account security
# TODO: Automate with Selenium
# TODO: Check for existing username already exists proton
# TODO: Bulk run and output to csv
