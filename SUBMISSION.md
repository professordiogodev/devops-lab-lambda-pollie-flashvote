# Submission

Fork URL: <!-- paste the URL of your fork here -->

## Files to commit

- [ ] `handler.py`: your Lambda function (the tests in `tests/` must pass)

## Questions

Answer in your own words. Where a question asks for output, paste it in a code block.

### Q1. Paste `aws dynamodb describe-table` for your table (key schema and billing mode). Why on-demand billing for a ten minute spike? What does `UpdateItem` with `ADD` guarantee that reading the number, adding one and writing it back does not?

**Your answer:**

<!-- replace this line with your answer -->

### Q2. Paste the JSON of your function role policy. Which actions and which resource? What could someone do with a leaked function if the policy were `dynamodb:*` on `*`?

**Your answer:**

<!-- replace this line with your answer -->

### Q3. Paste two `REPORT` lines from the CloudWatch logs of your function: one with `Init Duration` (cold start) and one without. What is a cold start and when does it matter for a live vote?

**Your answer:**

<!-- replace this line with your answer -->

### Q4. Paste the output of `./loadtest.sh` (200 votes, 20 in parallel) and the results it fetched. Why is the total exactly 200? What would you have seen with a read-then-write handler?

**Your answer:**

<!-- replace this line with your answer -->

### Q5. Your first deploy probably returned a 500. Paste the log lines of one failed invocation and say what you changed. Where did you find them and how long did it take?

**Your answer:**

<!-- replace this line with your answer -->

### Q6. Show the throttling you set on the API stage and the log retention of your log group. What does each protect you from? Estimate the cost of 1 million votes (say which prices you used and where you found them).

**Your answer:**

<!-- replace this line with your answer -->

### Q7. Pollie also has a worker that reads from Redis all day and a PostgreSQL database. Name one part of Pollie you would NOT move to Lambda and why.

**Your answer:**

<!-- replace this line with your answer -->

### Q8. Paste the output of `./verify.sh`. It must end with **ALL CHECKS PASSED**.

**Your answer:**

<!-- replace this line with your answer -->

### Q9. **Tear down.** Paste the output of `./verify-teardown.sh`. It must end with **TEARDOWN VERIFIED**.

**Your answer:**

<!-- replace this line with your answer -->
