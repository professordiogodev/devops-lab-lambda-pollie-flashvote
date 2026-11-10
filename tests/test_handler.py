"""Local tests for handler.py. DynamoDB is faked by moto, so no AWS account is needed.

Run:  pip install -r tests/requirements.txt && python3 -m pytest -q
"""
import base64
import importlib
import json
import os
import sys

import boto3
import pytest
from moto import mock_aws

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

os.environ.update(
    AWS_ACCESS_KEY_ID="test", AWS_SECRET_ACCESS_KEY="test", AWS_DEFAULT_REGION="us-east-1",
    TABLE="pollie-flashvote", OPTIONS="python,go,rust",
)


@pytest.fixture()
def handler():
    with mock_aws():
        boto3.client("dynamodb").create_table(
            TableName="pollie-flashvote",
            AttributeDefinitions=[
                {"AttributeName": "pk", "AttributeType": "S"},
                {"AttributeName": "sk", "AttributeType": "S"},
            ],
            KeySchema=[
                {"AttributeName": "pk", "KeyType": "HASH"},
                {"AttributeName": "sk", "KeyType": "RANGE"},
            ],
            BillingMode="PAY_PER_REQUEST",
        )
        import handler as h

        importlib.reload(h)
        yield h


def event(method, poll, suffix, body=None, b64=False):
    e = {
        "version": "2.0",
        "rawPath": f"/polls/{poll}/{suffix}",
        "requestContext": {"http": {"method": method}},
        "pathParameters": {"poll_id": poll},
        "isBase64Encoded": b64,
    }
    if body is not None:
        e["body"] = base64.b64encode(body.encode()).decode() if b64 else body
    return e


def call(h, *args, **kw):
    r = h.lambda_handler(event(*args, **kw), None)
    assert set(r) >= {"statusCode", "body"}, "a response needs statusCode and body"
    return r["statusCode"], json.loads(r["body"])


def test_vote_counts_up(handler):
    assert call(handler, "POST", "p1", "votes", '{"option": "python"}')[1]["count"] == 1
    status, body = call(handler, "POST", "p1", "votes", '{"option": "python"}')
    assert status == 200 and body["count"] == 2 and body["option"] == "python"


def test_results_lists_every_option_even_with_zero_votes(handler):
    call(handler, "POST", "p2", "votes", '{"option": "go"}')
    status, body = call(handler, "GET", "p2", "results")
    assert status == 200
    assert body["results"] == {"python": 0, "go": 1, "rust": 0}
    assert body["total"] == 1


def test_polls_are_separate(handler):
    call(handler, "POST", "a", "votes", '{"option": "rust"}')
    assert call(handler, "GET", "b", "results")[1]["total"] == 0


@pytest.mark.parametrize("body", ["not json", "", "[]", '{"option": 7}', '{"option": "java"}', "{}"])
def test_bad_votes_are_400_not_500(handler, body):
    status, body = call(handler, "POST", "p3", "votes", body)
    assert status == 400 and "error" in body


def test_missing_body_is_400(handler):
    assert call(handler, "POST", "p3", "votes")[0] == 400


def test_base64_body_is_decoded(handler):
    assert call(handler, "POST", "p4", "votes", '{"option": "go"}', b64=True)[0] == 200


@pytest.mark.parametrize("poll", ["UPPER", "has space", "x" * 41, "a/b", ""])
def test_bad_poll_ids_are_400(handler, poll):
    assert call(handler, "GET", poll, "results")[0] == 400


def test_unknown_route_is_404(handler):
    assert call(handler, "DELETE", "p5", "votes")[0] == 404


def test_every_response_is_json(handler):
    r = handler.lambda_handler(event("GET", "p6", "results"), None)
    assert r["headers"]["content-type"] == "application/json"
