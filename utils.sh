if_null() {
  if [ "${1}" = "" ] || [ "${1}" = "null" ]; then
    return 0
  else
    return 1
  fi
}

