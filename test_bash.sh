#!/bin/bash

#set -x

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

# Check script dependencies
check_installed "curl" "jq" "unzip"

# Check for chromedriver, install if missing
if ! command -v chromedriver &> /dev/null; then
  chromedriver_link=$(curl -s -S https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json | jq -r ".channels.Stable.downloads.chromedriver[0].url")
  if [ -z "$chromedriver_link" ]; then
    echo "Error, failed to find download link for chromedriver"
    exit 1
  fi
  chromedriver_bin="/tmp/chromedriver.zip"
  chromedriver_fold="/tmp/chromedriver-linux64"
  [ -f "$chromedriver_bin" ] && rm -rf "$chromedriver_bin"
  [ -d "$chromedriver_fold" ] && rm -rf "$chromedriver_fold"
  curl -s -S -o "$chromedriver_bin" "$chromedriver_link"
  if [ ! -s "$chromedriver_bin" ]; then
    echo "Error, failed to download chromedriver from link:
  $chromedriver_link"
    exit 1
  fi
  unzip "$chromedriver_bin" -d "/tmp"
  sudo mv "$chromedriver_fold/chromedriver" /usr/bin/chromedriver
  sudo chown root:root /usr/bin/chromedriver
  sudo chmod +x /usr/bin/chromedriver
fi

#chromedriver


#check_installed "default-jdk" "libxi6" "libgconf-2-4" "unzip" "xvfb"


SELENIUM="$(dirname "$0")/shellnium/lib/selenium.sh"
source "$SELENIUM"

main() {
    # Open the URL
    navigate_to 'https://google.com'

    # Get the search box
    local searchBox=$(find_element 'name' 'q')

    # send keys
    send_keys $searchBox "panda\n"
}

main
