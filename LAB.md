# LAB | Serverless: 2,000 Votes in Ten Minutes

## The situation

```text
EVENT BRIEF - main stage                                  Friday afternoon
Question    : "Which language should the next workshop teach?"
Audience    : 2,000 people
Voting open : 10 minutes
After that  : nothing, ever again
Organisers  : pay only for the votes that happen
              survive the spike without anyone touching a server
              keep the bill capped if a bot is pointed at it
```

Your Pollie stack from the last weeks is a few servers that run all month. Scaling them for ten minutes means planning, load balancers and a bill for capacity that sits idle 99.9% of the time. That is the job serverless was made for. You will build the voting endpoint with **API Gateway (HTTP API), Lambda and DynamoDB**, then break it, load it and prove it.

> **Your mission**
> - Write the Lambda function: `POST /polls/{poll_id}/votes` and `GET /polls/{poll_id}/results`
> - Count votes with **one atomic DynamoDB update** so that 200 votes sent in parallel are exactly 200
> - Give the function **least privilege** (one table, two actions) and a **brake** on cost (throttling, log retention, small memory)
> - Read the logs when it breaks, and run a load test
> - Tear it all down and prove it

**Time:** 105-120 min | **Cost:** free tier, well under one cent | **You need:** an AWS account where you are an administrator, the AWS CLI v2, Python 3.11+, curl and a terminal. Everything here is named `pollie-flashvote`, in one region, so `./teardown.sh` can remove it.

---

## Part 0 - Set the scene

1. **Fork** this repository, clone it and open it in your editor. Check that the CLI works and note the region:

```bash
aws sts get-caller-identity
aws configure get region
```

2. Prepare the local test loop. The tests fake DynamoDB with `moto`, so you can write the function **before** you pay for or deploy anything:

```bash
python3 -m venv .venv
.venv/bin/pip install -r tests/requirements.txt
.venv/bin/python -m pytest -q
```

Everything fails today: `handler.py` is a skeleton with four TODOs.

> **Think** The tests run in 2 seconds and cost nothing. Why is a fast local loop worth more on Lambda than deploying after every edit? How long does one deploy-and-try cycle take you later in this lab?

---

## Part 1 - The function

Open `handler.py` and write `lambda_handler` until `pytest` is green. Read the event description at the top of the file; this is the API Gateway "payload format 2.0" event.

Rules the tests (and later the real API) enforce:

| Request | Answer |
|---------|--------|
| `POST /polls/keynote/votes` with `{"option": "go"}` | `200` and `{"poll_id", "option", "count"}` where `count` is the new total for that option |
| `GET /polls/keynote/results` | `200` and `{"poll_id", "results": {"python": 3, "go": 0, "rust": 1}, "total": 4}` (every option, zeros included) |
| bad JSON, empty body, unknown option, bad poll id | `400` with `{"error": "..."}`. **Never a 500**: a bot's garbage is not your outage |
| anything else | `404` |

The data model is fixed: one DynamoDB item per poll and option, with partition key `pk` (the poll id), sort key `sk` (the option) and a number attribute `votes`.

> **Think** Reading `votes`, adding one in Python and writing it back looks correct. Two Lambdas run it at the same moment. What is the final number? Which DynamoDB update expression avoids the problem without any locking?

---

## Part 2 - The table and the role (the console, then the CLI)

1. In the **DynamoDB console**, create the table `pollie-flashvote`: partition key `pk` (String), sort key `sk` (String), **On-demand** capacity. Look at every setting you did not change. Then find the CLI command that does the same (`aws dynamodb create-table help`) and write it down in your notes: next time you will not click.
2. Create an **IAM role** `pollie-flashvote-role` that the Lambda service may assume (trust policy: principal `lambda.amazonaws.com`, action `sts:AssumeRole`).
3. Give it exactly two things:
   - the AWS managed policy `AWSLambdaBasicExecutionRole` (only lets it write logs);
   - **one inline policy** with the two DynamoDB actions the function really uses, on the ARN of **this table only** (`arn:aws:dynamodb:<region>:<account>:table/pollie-flashvote`).

> **Think** Look at what `AWSLambdaBasicExecutionRole` allows. Then write the other policy as if you were the attacker who found a bug in your function and can run any code with its role. What can they reach with `dynamodb:*` on `*`? And with your policy?

---

## Part 3 - Deploy the function

Package and create it. Use the **arm64** architecture (cheaper) and a current Python runtime, a 5 second timeout and the smallest memory, and pass the table name and the options through **environment variables**:

```bash
zip function.zip handler.py
aws lambda create-function --function-name pollie-flashvote ... \
  --environment '{"Variables":{"TABLE":"pollie-flashvote","OPTIONS":"python,go,rust"}}'
```

(Fill in the `...` yourself with `aws lambda create-function help`. If the role was created seconds ago and the command says it cannot assume it, wait ten seconds: IAM is eventually consistent.)

Invoke it directly with a test event, the way the console "Test" button does. Build the event with the same shape the tests use (`tests/test_handler.py` has a helper), save it as `event.json` and run:

```bash
aws lambda invoke --function-name pollie-flashvote --cli-binary-format raw-in-base64-out --payload file://event.json out.json && cat out.json
```

Now set the **log retention** of `/aws/lambda/pollie-flashvote` to 7 days. By default logs are kept **forever** and you pay for storage forever.

> **Think** Lambda bills for duration in milliseconds, multiplied by memory. A function that is I/O-bound (it waits for DynamoDB) gets nothing from more memory. When *would* more memory make a function cheaper overall?

---

## Part 4 - The front door (API Gateway HTTP API)

Create an **HTTP API** (not REST API; look up why it is the cheaper, simpler choice here) named `pollie-flashvote`:

1. one **Lambda proxy integration**, payload format **2.0**;
2. exactly two routes, both to that integration: `POST /polls/{poll_id}/votes` and `GET /polls/{poll_id}/results`;
3. the stage `$default` with **auto-deploy** and **default route throttling** (for example rate 50, burst 100);
4. a **resource-based permission on the function** so that *this API and no other caller* may invoke it (`aws lambda add-permission`, principal `apigateway.amazonaws.com`, a `--source-arn` with your API id).

(The console wizard does steps 1-3 in a few clicks and the permission for you. Using the wizard once and then reading what it created with `aws apigatewayv2 get-routes`, `get-integrations` and `aws lambda get-policy` is a fine way to learn it; so is the CLI from the start.)

Try it:

```bash
API=$(aws apigatewayv2 get-apis --query "Items[?Name=='pollie-flashvote']|[0].ApiEndpoint" --output text)
curl -s -X POST "$API/polls/keynote/votes" -d '{"option":"go"}'
curl -s "$API/polls/keynote/results"
```

> **Think** The URL is public and anyone can call it. What exactly does the throttling protect, and what does it *not* protect against (think: whose money is being spent)? What would you add in front of a real production API?

---

## Part 5 - Break it, read the logs

Your first deploy rarely works the first time. When a call returns `{"message":"Internal Server Error"}`, API Gateway tells you nothing. The truth is in CloudWatch Logs:

```bash
aws logs tail /aws/lambda/pollie-flashvote --since 10m
```

Find the stack trace of one failed invocation. (If nothing failed, cause one: change the table name in the environment variable and call the API; then fix it.) Look at the `REPORT` lines: duration, billed duration, memory used and, on the first call after a deploy, `Init Duration` — the **cold start**.

> **Think** How would you know your endpoint is failing *before* a conference attendee tells you? Name the metric and what you would alarm on.

---

## Part 6 - The load test

```bash
./loadtest.sh 200 20
```

It sends 200 votes, 20 at a time, to a fresh poll and prints the results. The total must be **exactly 200**. Then try `./loadtest.sh 1000 50`. Look at the timing, at the HTTP status codes counted at the top (any `429`? that is your throttle working), and at how many Lambda environments started (`REPORT` lines with `Init Duration`).

> **Think** You did not provision, scale or patch anything. Where did the 20 parallel executions run? What would the same spike do to a single small EC2 instance behind nginx?

---

## Part 7 - Prove it

```bash
./verify.sh
```

It tests your code, reads your resources back from AWS (table keys and billing, runtime, memory, role policies, log retention, routes, throttling, who may invoke the function) and then votes against your real endpoint, including bad requests and 60 parallel votes. Fix what is red and run it again until it ends with **ALL CHECKS PASSED**.

> **Stuck?** `Internal Server Error`: read the logs (Part 5). `AccessDeniedException` in the logs: your role policy misses an action or has the wrong ARN. `Unable to assume role`: wait and retry. `AccessDenied` calling the API from curl is not possible: it is public, so look at routes and the integration. Changed `handler.py`? Zip and run `aws lambda update-function-code` again.

---

## Level up (optional)

- Add a `GET /polls/{poll_id}/results` response header `cache-control: max-age=2`. What does it save during the stage vote?
- Create a CloudWatch **alarm** on the `Errors` metric of the function with an email action (SNS). Do not forget to delete them in the teardown.
- Move the write behind an **SQS queue** so a DynamoDB hiccup does not lose votes. What changes for the person who voted?
- Translate the whole stack into Terraform (`aws_lambda_function`, `aws_apigatewayv2_api`, `aws_dynamodb_table`). How many resources is it?

<!-- teardown:start (generated by labs.py, do not edit) -->
## Tear down (mandatory)

Resources left behind cost money, keep doors open and pollute the next lab. Removing what you created is part of the job, so it is part of the submission: **you must prove it is gone**.

Do this **last**, after you have pasted your `verify` output into `SUBMISSION.md` (once you tear down, the lab can no longer be verified).

1. Run `./teardown.sh`. It deletes the HTTP API, the Lambda function, its log group, the IAM role and the DynamoDB table (all named `pollie-flashvote`). Code and answers stay.

Then run the proof:

```bash
./verify-teardown.sh
```

It prints a list of checks and must end with **TEARDOWN VERIFIED**. If it reports leftovers, remove them and run it again. Paste the full output in your submission.
<!-- teardown:end -->

<!-- submission:start (generated by labs.py, do not edit) -->
## Submission

Answer the questions in `SUBMISSION.md` in **your fork** (paste output in code blocks where asked), push, then submit the **URL of your fork**.

**Files to commit**

- `handler.py`: your Lambda function (the tests in `tests/` must pass)

**Questions to answer**

1. Paste `aws dynamodb describe-table` for your table (key schema and billing mode). Why on-demand billing for a ten minute spike? What does `UpdateItem` with `ADD` guarantee that reading the number, adding one and writing it back does not?
2. Paste the JSON of your function role policy. Which actions and which resource? What could someone do with a leaked function if the policy were `dynamodb:*` on `*`?
3. Paste two `REPORT` lines from the CloudWatch logs of your function: one with `Init Duration` (cold start) and one without. What is a cold start and when does it matter for a live vote?
4. Paste the output of `./loadtest.sh` (200 votes, 20 in parallel) and the results it fetched. Why is the total exactly 200? What would you have seen with a read-then-write handler?
5. Your first deploy probably returned a 500. Paste the log lines of one failed invocation and say what you changed. Where did you find them and how long did it take?
6. Show the throttling you set on the API stage and the log retention of your log group. What does each protect you from? Estimate the cost of 1 million votes (say which prices you used and where you found them).
7. Pollie also has a worker that reads from Redis all day and a PostgreSQL database. Name one part of Pollie you would NOT move to Lambda and why.
8. Paste the output of `./verify.sh`. It must end with **ALL CHECKS PASSED**.
9. **Tear down.** Paste the output of `./verify-teardown.sh`. It must end with **TEARDOWN VERIFIED**.
<!-- submission:end -->
