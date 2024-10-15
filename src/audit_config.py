import os, sys

base_path = os.path.dirname(__file__)
library_path = os.path.join(base_path, "../")
sys.path.append(os.path.abspath(library_path))
from dotenv import load_dotenv

load_dotenv(os.path.abspath(os.path.join(base_path, ".env")))

OPNEAI_VERSION = 3

# notes: Don't hardcode OPENAI_API_KEY here Use environment variables
GPT4_API = os.environ.get('OPENAI_API_KEY')
GPT3_API = os.environ.get('OPENAI_API_KEY')
fake_gpt_token = 'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6Ik1UaEVOVUpHTkVNMVFURTRNMEZCTWpkQ05UZzVNRFUxUlRVd1FVSkRNRU13UmtGRVFrRXpSZyJ9.eyJodHRwczovL2FwaS5vcGVuYWkuY29tL3Byb2ZpbGUiOnsiZW1haWwiOiJkZXZAbWV0YXRydXN0LmlvIiwiZW1haWxfdmVyaWZpZWQiOnRydWV9LCJodHRwczovL2FwaS5vcGVuYWkuY29tL2F1dGgiOnsicG9pZCI6Im9yZy1EYjZFSlVob3JvSGx2SEI1MGFpTjNYMDUiLCJ1c2VyX2lkIjoidXNlci1Qb3NKQWRSTFo0c0JhQ1BQU1JmNHZGQ3EifSwiaXNzIjoiaHR0cHM6Ly9hdXRoMC5vcGVuYWkuY29tLyIsInN1YiI6ImF1dGgwfDY0MTFjMGY5MTQ1M2NmY2EwZTNmMjY5YiIsImF1ZCI6WyJodHRwczovL2FwaS5vcGVuYWkuY29tL3YxIiwiaHR0cHM6Ly9vcGVuYWkub3BlbmFpLmF1dGgwYXBwLmNvbS91c2VyaW5mbyJdLCJpYXQiOjE2OTgwNjg2MTQsImV4cCI6MTY5ODkzMjYxNCwiYXpwIjoiVGRKSWNiZTE2V29USHROOTVueXl3aDVFNHlPbzZJdEciLCJzY29wZSI6Im9wZW5pZCBwcm9maWxlIGVtYWlsIG1vZGVsLnJlYWQgbW9kZWwucmVxdWVzdCBvcmdhbml6YXRpb24ucmVhZCBvcmdhbml6YXRpb24ud3JpdGUgb2ZmbGluZV9hY2Nlc3MifQ.DiFKq4v_j-xshiaqALPrWIoQ77gese2QbB_BPHSIYAt-f_s9dFhzIpJmpkjNzQoyLKLZBbozH-GE2TyRSCLH_q-lJIZ_GdAZFQn6r1uP863InIuA_QiptaGz8p6tsdJv-6B1LHXjKWtDY4DSwJcIOkb3BbJSIHgz_di6fzktlD7qXQXIwdUBzZWMMOEWX81Ijrm680DMcKw7cTsxtea3R_nY88zs-EblRMk8v4gJq6l6uoYRfhqqyPhgAliX1AjLfLKQQMlb6GqodsA4ZaJWeM4QHIuOc38bCXUiy2VeKGCcE42KNMDm7BqvdPxOaMD5h-3Ccgf3urmxayp3r8xJWA'

# os.environ['OPENAI_API_KEY'] = GPT3_API

SEND_PRICE = 0.0015 / 1000
RECEIVE_PRICE = 0.002 / 1000

GPT4_SEND_PRICE = 0.03 / 1000
GPT4_RECEIVE_PRICE = 0.06 / 1000
