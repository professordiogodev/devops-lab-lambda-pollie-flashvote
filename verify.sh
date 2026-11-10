#!/usr/bin/env bash
# Checks what you built in AWS and then votes against it. Run with: ./verify.sh
# Do not use `set -o pipefail` with grep -q pipes: it races.
set -u
cd "$(dirname "$0")"
command -v aws >/dev/null || { echo "The AWS CLI is not installed." >&2; exit 1; }
ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || { echo "No working AWS credentials (aws sts get-caller-identity fails)." >&2; exit 1; }
REGION=$(aws configure get region 2>/dev/null); REGION=${AWS_REGION:-${AWS_DEFAULT_REGION:-${REGION:-us-east-1}}}
NAME=pollie-flashvote
echo "Account $ACCOUNT, region $REGION"
pass=0; failn=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS  $d"; pass=$((pass+1)); else echo "FAIL  $d"; failn=$((failn+1)); fi; }
q() { aws "$@" 2>/dev/null; }

echo "== Your code =="
PY=python3; [ -x .venv/bin/python ] && PY=.venv/bin/python
check "handler.py: the local tests pass (needs the .venv from Part 1)" bash -c "$PY -m pytest -q tests >/dev/null 2>&1"
check "no AWS keys written in the repository" bash -c "! grep -rE 'AKIA[0-9A-Z]{16}' . --exclude-dir=.git --exclude=verify.sh"

echo "== DynamoDB =="
TBL=$(q dynamodb describe-table --table-name $NAME --output json)
check "table $NAME exists with keys pk (HASH) and sk (RANGE), both strings" python3 -c "
import json,sys
t=json.loads(sys.argv[1]); k={x['AttributeName']:x['KeyType'] for x in t['Table']['KeySchema']}
a={x['AttributeName']:x['AttributeType'] for x in t['Table']['AttributeDefinitions']}
assert k=={'pk':'HASH','sk':'RANGE'} and a=={'pk':'S','sk':'S'}" "${TBL:-{\}}"
check "billing mode is on-demand (PAY_PER_REQUEST)" python3 -c "
import json,sys; t=json.loads(sys.argv[1]); assert t['Table'].get('BillingModeSummary',{}).get('BillingMode')=='PAY_PER_REQUEST'" "${TBL:-{\}}"

echo "== Lambda =="
FN=$(q lambda get-function-configuration --function-name $NAME --output json)
check "function $NAME exists, Python 3.11+ runtime" python3 -c "
import json,sys; c=json.loads(sys.argv[1]); r=c['Runtime']; assert r.startswith('python3.') and int(r.split('.')[1])>=11" "${FN:-{\}}"
check "handler is handler.lambda_handler" python3 -c "
import json,sys; assert json.loads(sys.argv[1])['Handler']=='handler.lambda_handler'" "${FN:-{\}}"
check "timeout 10s or less and memory 256 MB or less (a vote is tiny; do not buy a big box)" python3 -c "
import json,sys; c=json.loads(sys.argv[1]); assert c['Timeout']<=10 and c['MemorySize']<=256" "${FN:-{\}}"
check "environment has TABLE=$NAME and OPTIONS with at least 3 options" python3 -c "
import json,sys; e=json.loads(sys.argv[1])['Environment']['Variables']; assert e['TABLE']=='$NAME' and len([o for o in e['OPTIONS'].split(',') if o.strip()])>=3" "${FN:-{\}}"
ROLE=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['Role'].split('/')[-1])" "${FN:-{\}}" 2>/dev/null)

echo "== IAM: least privilege =="
check "the function role exists" test -n "$ROLE" -a -n "$(q iam get-role --role-name "${ROLE:-none}" --query Role.Arn --output text)"
POLDOCS=$(python3 - "$ROLE" <<'PY' 2>/dev/null
import json,subprocess,sys
role=sys.argv[1]
def aws(*a): return json.loads(subprocess.check_output(("aws",)+a+("--output","json")))
docs=[]
for n in aws("iam","list-role-policies","--role-name",role)["PolicyNames"]:
    docs.append(aws("iam","get-role-policy","--role-name",role,"--policy-name",n)["PolicyDocument"])
managed=[]
for p in aws("iam","list-attached-role-policies","--role-name",role)["AttachedPolicies"]:
    managed.append(p["PolicyName"])
    if not p["PolicyArn"].startswith("arn:aws:iam::aws:"):
        v=aws("iam","get-policy","--policy-arn",p["PolicyArn"])["Policy"]["DefaultVersionId"]
        docs.append(aws("iam","get-policy-version","--policy-arn",p["PolicyArn"],"--version-id",v)["PolicyVersion"]["Document"])
print(json.dumps({"docs":docs,"managed":managed}))
PY
)
check "only AWS managed policy attached is AWSLambdaBasicExecutionRole (logs), nothing broader" python3 -c "
import json,sys; m=json.loads(sys.argv[1])['managed']; assert set(m)<={'AWSLambdaBasicExecutionRole'}" "${POLDOCS:-{\}}"
check "no wildcard in any Action of your own policies (no dynamodb:*, no *)" python3 -c "
import json,sys
for d in json.loads(sys.argv[1])['docs']:
    for s in (d['Statement'] if isinstance(d['Statement'],list) else [d['Statement']]):
        for a in ([s['Action']] if isinstance(s['Action'],str) else s['Action']):
            assert '*' not in a, a" "${POLDOCS:-{\}}"
check "the DynamoDB statement is limited to this one table ARN (no * in Resource)" python3 -c "
import json,sys
docs=json.loads(sys.argv[1])['docs']; assert docs
found=False
for d in docs:
    for s in (d['Statement'] if isinstance(d['Statement'],list) else [d['Statement']]):
        rs=[s['Resource']] if isinstance(s['Resource'],str) else s['Resource']
        assert all('*' not in r for r in rs), rs
        if any(r.endswith(':table/$NAME') for r in rs): found=True
assert found" "${POLDOCS:-{\}}"
check "the role can write counters but cannot delete or scan (no DeleteItem, Scan, DeleteTable)" python3 -c "
import json,sys
acts=set()
for d in json.loads(sys.argv[1])['docs']:
    for s in (d['Statement'] if isinstance(d['Statement'],list) else [d['Statement']]):
        acts|=set([s['Action']] if isinstance(s['Action'],str) else s['Action'])
assert 'dynamodb:UpdateItem' in acts and not (acts & {'dynamodb:DeleteItem','dynamodb:Scan','dynamodb:DeleteTable','dynamodb:PutItem'})" "${POLDOCS:-{\}}"

echo "== Logs =="
RET=$(q logs describe-log-groups --log-group-name-prefix /aws/lambda/$NAME --query "logGroups[?logGroupName=='/aws/lambda/$NAME']|[0].retentionInDays" --output text)
check "log group retention is set (a number of days, not 'never expire')" bash -c "[ '$RET' != None ] && [ -n '$RET' ] && [ '$RET' -le 365 ]"

echo "== API Gateway =="
API=$(q apigatewayv2 get-apis --query "Items[?Name=='$NAME']|[0]" --output json)
APIID=$(python3 -c "import json,sys; print((json.loads(sys.argv[1]) or {}).get('ApiId',''))" "${API:-null}" 2>/dev/null)
URL=$(python3 -c "import json,sys; print((json.loads(sys.argv[1]) or {}).get('ApiEndpoint',''))" "${API:-null}" 2>/dev/null)
check "an HTTP API named $NAME exists" test -n "$APIID"
check "its routes are exactly POST /polls/{poll_id}/votes and GET /polls/{poll_id}/results" bash -c "
r=\$(aws apigatewayv2 get-routes --api-id '${APIID:-x}' --query 'Items[].RouteKey' --output text | tr '\t' '\n' | sort | tr '\n' '|')
[ \"\$r\" = 'GET /polls/{poll_id}/results|POST /polls/{poll_id}/votes|' ]"
STAGE=$(q apigatewayv2 get-stage --api-id "${APIID:-x}" --stage-name '$default' --output json)
check "stage \$default has throttling set (rate and burst), a brake on the bill" python3 -c "
import json,sys; s=json.loads(sys.argv[1])['DefaultRouteSettings']; assert s['ThrottlingRateLimit']>0 and s['ThrottlingBurstLimit']>0" "${STAGE:-{\}}"
POL=$(q lambda get-policy --function-name $NAME --query Policy --output text)
check "only this API may invoke the function (permission has a SourceArn with the API id)" python3 -c "
import json,sys
p=json.loads(sys.argv[1]); assert p['Statement']
for s in p['Statement']:
    assert s['Principal']=={'Service':'apigateway.amazonaws.com'}
    assert '$APIID' in json.dumps(s['Condition'])" "${POL:-{\}}"

echo "== Live: vote against the real endpoint =="
if [ -n "$URL" ]; then
  P="verify-$(date +%s)-$RANDOM"
  code() { curl -s -o /tmp/.fv.$$ -w '%{http_code}' --max-time 15 "$@"; }
  check "POST a vote for python: 200 and count 1" bash -c "[ \"\$(curl -s --max-time 15 -X POST '$URL/polls/$P/votes' -d '{\"option\":\"python\"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)[\"count\"])')\" = 1 ]"
  curl -s --max-time 15 -X POST "$URL/polls/$P/votes" -d '{"option":"go"}' >/dev/null
  curl -s --max-time 15 -X POST "$URL/polls/$P/votes" -d '{"option":"go"}' >/dev/null
  check "GET results: python 1, go 2, rust 0, total 3" bash -c "curl -s --max-time 15 '$URL/polls/$P/results' | python3 -c '
import json,sys; d=json.load(sys.stdin); assert d[\"results\"]=={\"python\":1,\"go\":2,\"rust\":0} and d[\"total\"]==3, d'"
  check "an unknown option is 400" test "$(code -X POST "$URL/polls/$P/votes" -d '{"option":"cobol"}')" = 400
  check "invalid JSON is 400, not 500" test "$(code -X POST "$URL/polls/$P/votes" -d 'not json')" = 400
  check "an empty body is 400, not 500" test "$(code -X POST "$URL/polls/$P/votes")" = 400
  check "a bad poll id is 400" test "$(code "$URL/polls/BAD%20ID/results")" = 400
  check "an unknown route is 404" test "$(code "$URL/nothing-here")" = 404
  Q="par-$(date +%s)-$RANDOM"
  seq 1 60 | xargs -P 15 -I{} curl -s -o /dev/null --max-time 20 -X POST "$URL/polls/$Q/votes" -d '{"option":"rust"}'
  check "60 votes sent 15 at a time are counted exactly (60, none lost, none twice)" bash -c "curl -s --max-time 15 '$URL/polls/$Q/results' | python3 -c '
import json,sys; d=json.load(sys.stdin); assert d[\"results\"][\"rust\"]==60, d'"
  rm -f /tmp/.fv.$$
else
  echo "FAIL  no endpoint to test (the HTTP API does not exist yet)"; failn=$((failn+1))
fi

echo
if [ "$failn" -eq 0 ]; then echo "ALL CHECKS PASSED ($pass/$pass)"; else echo "$failn check(s) failed, $pass passed"; fi
exit "$failn"
