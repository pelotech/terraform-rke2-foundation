# blob_put URL FILE CONTENT_TYPE ATTEMPTS puts FILE as a block blob at URL with the identity CLIENT_ID.
blob_put() {
  local url="$1" file="$2" content_type="$3" attempts="$4" token
  for _ in $(seq 1 "$attempts"); do
    if token=$(imds_token https://storage.azure.com/) \
      && curl -sf -X PUT -H "Authorization: Bearer $token" -H "x-ms-version: 2021-08-06" -H "x-ms-blob-type: BlockBlob" \
        -H "Content-Type: $content_type" --data-binary @"$file" "$url"; then
      return 0
    fi
    sleep 10
  done
  echo "blob-put: could not upload $url" >&2
  return 1
}
