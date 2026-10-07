#!/usr/bin/env bash
# Local stand-in for the blob container: put_snapshot copies the file under /var/tmp/rke2-snapshot-uploads.
put_snapshot() {
  install -D -m 0600 "$2" "/var/tmp/rke2-snapshot-uploads/$1"
}
