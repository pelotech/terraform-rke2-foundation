# Prints an access token for the resource in $1, from the VM's managed identity CLIENT_ID.
imds_token() {
  curl -sf -H Metadata:true "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$1&client_id=$CLIENT_ID" \
    | python3 -c 'import json, sys; print(json.load(sys.stdin)["access_token"])'
}
