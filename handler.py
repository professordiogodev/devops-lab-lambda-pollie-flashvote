"""Pollie flash vote: the Lambda function behind the API Gateway HTTP API.

API Gateway (payload format 2.0) calls lambda_handler(event, context) with, among other things:
  event["requestContext"]["http"]["method"]   "POST" or "GET"
  event["rawPath"]                            "/polls/keynote/votes"
  event["pathParameters"]["poll_id"]          "keynote"
  event["body"]                               the request body as a string (may be missing)
  event["isBase64Encoded"]                    True if the body is base64 text

It must return {"statusCode": ..., "headers": {...}, "body": "<a JSON string>"}.

Environment variables set on the function: TABLE (the DynamoDB table name) and
OPTIONS (comma separated, for example "python,go,rust").
"""
import json
import os

import boto3

TABLE = os.environ.get("TABLE", "pollie-flashvote")
OPTIONS = [o.strip() for o in os.environ.get("OPTIONS", "").split(",") if o.strip()]


def lambda_handler(event, context):
    # TODO 1: poll_id must be 1-40 characters of a-z, 0-9 and "-". Anything else: 400.
    # TODO 2: POST /polls/{poll_id}/votes with body {"option": "go"}
    #         - invalid JSON, a body that is not an object, a missing or unknown option: 400, never 500
    #         - otherwise add ONE vote with a single atomic DynamoDB update
    #           (item key: pk = poll id, sk = option; attribute: votes) and answer 200
    #           {"poll_id": ..., "option": ..., "count": <the new total for that option>}
    # TODO 3: GET /polls/{poll_id}/results -> 200
    #           {"poll_id": ..., "results": {"python": 3, "go": 0, "rust": 1}, "total": 4}
    #         every option appears, with 0 when nobody voted for it
    # TODO 4: any other method/path: 404 {"error": "not found"}
    # Every response is JSON with the header content-type: application/json
    raise NotImplementedError("write me")
