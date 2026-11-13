# Sourced by a step, never run on its own: sets DBX_TOKEN in that step's shell
# and nowhere else, so no token is passed between steps.
#
# Exchanges the job's GitHub OIDC token (audience = the account ID) for a
# Databricks token as the automation principal, at the account's token
# endpoint. The same exchange the SDK's github-oidc auth makes internally.
# Needs DATABRICKS_HOST, DATABRICKS_ACCOUNT_ID, DATABRICKS_CLIENT_ID and the
# job permission id-token: write.

gh_jwt=$(curl -sfS -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${DATABRICKS_ACCOUNT_ID}" | jq -r .value)
echo "::add-mask::$gh_jwt"
_resp=$(curl -sS -w '\n%{http_code}' -X POST "$DATABRICKS_HOST/oidc/accounts/$DATABRICKS_ACCOUNT_ID/v1/token" \
  --data-urlencode "grant_type=urn:ietf:params:oauth:grant-type:token-exchange" \
  --data-urlencode "subject_token=$gh_jwt" \
  --data-urlencode "subject_token_type=urn:ietf:params:oauth:token-type:jwt" \
  --data-urlencode "client_id=$DATABRICKS_CLIENT_ID" \
  --data-urlencode "scope=all-apis")
unset gh_jwt
DBX_TOKEN=$(head -n -1 <<<"$_resp" | jq -r '.access_token // empty')
[ -n "$DBX_TOKEN" ] && echo "::add-mask::$DBX_TOKEN"
echo "- token exchange: HTTP $(tail -n1 <<<"$_resp")" | tee -a "$GITHUB_STEP_SUMMARY"
if [ -z "$DBX_TOKEN" ]; then
  head -n -1 <<<"$_resp" | jq '{error, error_description}'
  exit 1
fi
unset _resp
