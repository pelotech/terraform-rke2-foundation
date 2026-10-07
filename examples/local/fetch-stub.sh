#!/usr/bin/env bash
# Local stand-in for the cloud secret store: run.sh seeds /tmp/rke2-seed before bootstrap runs.
fetch() {
  install -D -m 0600 "/tmp/rke2-seed/$2" "$SECRET_DIR/$2"
  rm -f "/tmp/rke2-seed/$2"
}
